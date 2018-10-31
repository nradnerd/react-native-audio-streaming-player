//
//  MyObjcClass.h
//  use_nativeModules
//
//  Created by Q on 2016. 8. 25..
//  Copyright © 2016년 Facebook. All rights reserved.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@import AVFoundation;

@interface RNAudioPlayer : RCTEventEmitter<RCTBridgeModule>

@property (strong, nonatomic) AVPlayerItem *playerItem;
@property (strong, nonatomic) AVPlayer *player;
@property (nonatomic, readwrite) BOOL isPlayingWithOthers;

@end
