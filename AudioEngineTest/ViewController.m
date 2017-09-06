//
//  ViewController.m
//  AudioEngineTest
//
//  Created by Johan Thorell on 2017-09-06.
//  Copyright © 2017 Johan Thorell. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()
@property (nonatomic) AVAudioEngine* audioEngine;
@property (nonatomic) Float64 sampleRate;
@property (nonatomic) double theta;
- (void)reinitialize;
- (void)startAudioEngine;
- (void)startAudioEngineInternal;
- (void)pauseAudioEngine;
- (void)stopAudioEngine;
@end


static void CheckResult(OSStatus result, const char *operation)
{
	if (result == noErr) return;
	
	char errorString[20];
	// see if it appears to be a 4-char-code
	*(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(result);
	if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
		errorString[0] = errorString[5] = '\'';
		errorString[6] = '\0';
	} else
		// no, format it as an integer
		sprintf(errorString, "%d", (int)result);
	
	fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
	
	exit(1);
}
static OSStatus renderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData)
{
	// Fixed amplitude is good enough for our purposes
	const double amplitude = 0.25;
	
	// Get the tone parameters out of the view controller
	ViewController *viewController = (__bridge ViewController *)inRefCon;
	double theta = viewController.theta;
	double theta_increment = 2.0 * M_PI * 1500 / viewController.sampleRate;
	
	// This is a mono tone generator so we only need the first buffer
	const int channel = 0;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	// Generate the samples
	for (UInt32 frame = 0; frame < inNumberFrames; frame++)
	{
		buffer[frame] = sin(theta) * amplitude;
		
		theta += theta_increment;
		if (theta > 2.0 * M_PI)
		{
			theta -= 2.0 * M_PI;
		}
	}
	
	// Store the updated theta back in the view controller
	viewController.theta = theta;
	
	return noErr;
}
static AudioStreamBasicDescription AudioUnitStreamInputFormat (double iSampleRate) {
	AudioStreamBasicDescription asbd;
	asbd.mSampleRate = iSampleRate;
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
	asbd.mFramesPerPacket = 1;
	asbd.mChannelsPerFrame = 2;
	asbd.mBytesPerFrame = asbd.mBytesPerPacket = 0;
	asbd.mReserved = 0;
	int wordsize = 4;
	asbd.mBitsPerChannel = wordsize * 8;
	asbd.mBytesPerFrame = asbd.mBytesPerPacket = wordsize;
	
	return asbd;
}
static void streamFormatCallback( void* inRefCon, AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement)
{
	NSLog(@"called streamFormat");
#pragma unused(inID, inUnit)
	dispatch_async(dispatch_get_main_queue(), ^{
		ViewController* audioController = (__bridge ViewController *)inRefCon;
		if( inScope == kAudioUnitScope_Output && inElement == 0 ) {
			[audioController reinitialize];
			AudioStreamBasicDescription asbd;
			UInt32 dataSize = sizeof( asbd );
			OSStatus result = AudioUnitGetProperty(audioController.audioEngine.outputNode.audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &asbd, &dataSize );
			CheckResult(result, "Could not get stream format");
			
			if ( audioController.sampleRate != asbd.mSampleRate )
			{
				
				AudioStreamBasicDescription audioUnitStreamInputFormat = AudioUnitStreamInputFormat(asbd.mSampleRate);
				result = AudioUnitSetProperty(audioController.audioEngine.outputNode.audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioUnitStreamInputFormat, sizeof(AudioStreamBasicDescription));
				audioController.sampleRate = asbd.mSampleRate;
				CheckResult(result, "Could not set stream format");
				[audioController startAudioEngine];
			}
		}
		
	});
}



@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self initializeAudioEngine];
	[self setupAudioSession];
	[self startAudioEngine];

}
- (void)initializeAudioEngine {
	_audioEngine = [AVAudioEngine new];
	AURenderCallbackStruct renderCallbackStruct;
	renderCallbackStruct.inputProc = &renderCallback;
	renderCallbackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
	OSStatus result = AudioUnitSetProperty(_audioEngine.outputNode.audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &renderCallbackStruct, sizeof(renderCallbackStruct));
	CheckResult(result, "Could not set render callback");
	
	result = AudioUnitAddPropertyListener(_audioEngine.outputNode.audioUnit, kAudioUnitProperty_StreamFormat, streamFormatCallback, (__bridge void* _Nullable)(self));
	CheckResult(result, "Could not add property listener");
	
	AudioStreamBasicDescription audioUnitStreamInputFormat = AudioUnitStreamInputFormat([AVAudioSession sharedInstance].sampleRate);
	
	result = AudioUnitSetProperty(_audioEngine.outputNode.audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioUnitStreamInputFormat, sizeof(AudioStreamBasicDescription));
	CheckResult(result, "Could not set stream format property listener");
}
- (void)setupAudioSession {
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	_sampleRate = audioSession.sampleRate;
	NSError *error = nil;
	BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
	success = [audioSession setActive:YES error:&error];
	if (error) {
		NSLog(@"%@", error.localizedDescription);
	}
}
- (void)startAudioEngine {
	
	[self startAudioEngineInternal];
}
- (void)startAudioEngineInternal {
	NSError *error = nil;
	[_audioEngine startAndReturnError:&error];
	if (error) {
		NSLog(@"%@", error.localizedDescription);
	}
}
- (void)pauseAudioEngine {
	[_audioEngine pause];
}
- (void)stopAudioEngine {
	[_audioEngine stop];
}
- (void)reinitialize {
	[_audioEngine reset];
	[_audioEngine stop];
	_audioEngine = nil;
	[self initializeAudioEngine];
	[self setupAudioSession];
}


@end
