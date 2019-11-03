
#import "RNAudioPlayer.h"
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTEventEmitter.h>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

static UIImage *_createColorImage(UIColor *color, CGRect imgBounds);
static UIImage *_defaultArtwork = nil;

static NSString *RNAudioPlaybackTimeElapsedNotification = @"RNAudioPlaybackTimeElapsedNotification";

@interface RNAudioPlayer() {
    BOOL stalled;
    NSString *artistName;
    NSString *songTitle;
    NSString *albumUrlStr;
    NSURL *albumUrl;
    NSDictionary *songInfo;
    MPMediaItemArtwork *albumArt;
    NSTimer *playbackTimeTimer;
    BOOL isSetup;
}

@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@implementation RNAudioPlayer

@synthesize bridge = _bridge;

+ (void)initialize
{
    _defaultArtwork = _createColorImage([UIColor whiteColor], CGRectMake(0, 0, 300, 300));
}

RCT_EXPORT_MODULE(RNAudioPlayer);

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        albumArt = [[MPMediaItemArtwork alloc] initWithImage: _defaultArtwork];
        isSetup = NO;
        
    }
    return self;
}

- (void)dealloc
{
    [playbackTimeTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self unregisterRemoteControlEvents];
    [self unregisterAudioInterruptionNotifications];
    [self deactivateAudioSession];
}

- (void)setup
{
    if (isSetup) return;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playbackTimeElapsed:)
                                                 name:RNAudioPlaybackTimeElapsedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                        selector:@selector(audioRouteChangeListenerCallback:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    playbackTimeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(playbackTimeTimer:)
                                                       userInfo:nil
                                                        repeats:YES];
    
    [self registerRemoteControlEvents];
    [self registerAudioInterruptionNotifications];
    
    isSetup = YES;
    
}

- (void)stopPlayer
{
    if (self.player) {
        if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) [self.player pause];
        self.player = nil;
    }
    
    if (self.playerItem) {
        
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.playerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemPlaybackStalledNotification
                                                      object:self.playerItem];
        self.playerItem = nil;
    }
    
    [self deactivateAudioSession];
}

#pragma mark - Pubic API

RCT_EXPORT_METHOD(play:(NSString *)url:(NSDictionary *)metadata)
{
    [self setup];
    
    [self stopPlayer];
    
    
    artistName = metadata[@"artist"];
    songTitle = metadata[@"title"];
    albumUrlStr = metadata[@"album_art_uri"];
    
    if (albumUrlStr != nil && [albumUrlStr isKindOfClass:[NSString class]]) {
        albumUrl = [NSURL URLWithString:albumUrlStr];
    } else {
        albumUrl = nil;
    }
    
    [self setNowPlayingInfo:true];
    
    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    self.playerItem = [AVPlayerItem playerItemWithURL:soundUrl];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    
    if ([[UIDevice currentDevice].systemVersion floatValue] >= 10) {
        self.player.automaticallyWaitsToMinimizeStalling = false;
    }
    
    [self.playerItem addObserver:self forKeyPath:@"status" options:0 context:nil];
    [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidPlayToEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemPlaybackStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:self.playerItem];
}

RCT_EXPORT_METHOD(pause)
{
    if (self.player && self.player.timeControlStatus != AVPlayerTimeControlStatusPaused) {
        [self.player pause];
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                        body: @{@"state": @"PAUSED" }];
        int duration = 0;
        if (self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);

        songInfo = @{
                     MPMediaItemPropertyTitle: artistName,
                     MPMediaItemPropertyArtist: songTitle,
                     MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat: 0.0],
                     MPMediaItemPropertyPlaybackDuration: [NSNumber numberWithFloat:duration],
                     MPNowPlayingInfoPropertyElapsedPlaybackTime: [NSNumber numberWithDouble:self.currentPlaybackTime],
                     MPMediaItemPropertyArtwork: albumArt
                     };
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = songInfo;
    }
}

RCT_EXPORT_METHOD(resume)
{
    if (self.player && self.player.timeControlStatus != AVPlayerTimeControlStatusPlaying) {
        [self.player play];
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                        body: @{@"state": @"PLAYING" }];
        [self activateAudioSession];
    }
}

RCT_EXPORT_METHOD(stop)
{
    [self stopPlayer];
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                    body: @{@"state": @"STOPPED" }];
}

RCT_EXPORT_METHOD(seekTo:(int) nSecond)
{
    CMTime newTime = CMTimeMakeWithSeconds(nSecond, 1);
    [self.player seekToTime:newTime];
}

RCT_EXPORT_METHOD(getMediaDuration:(RCTResponseSenderBlock)callback)
{
    int duration = 0;
    if (self.player && self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);
    callback(@[[NSNumber numberWithFloat:duration]]);
}

#pragma mark - Audio

- (void)playbackTimeTimer:(NSTimer *)timer
{
    @try {
        if (self.player) {
            if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
                NSNumber *time = [NSNumber numberWithDouble:CMTimeGetSeconds(self.player.currentTime)];
                [[NSNotificationCenter defaultCenter] postNotificationName:RNAudioPlaybackTimeElapsedNotification
                                                                    object:nil
                                                                  userInfo:@{@"time" : time}];
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"%@", ex);
    }
}

- (void)playbackTimeElapsed:(NSNotification *)notification
{
    
    NSNumber *position = [notification userInfo][@"time"];

    int duration = 0;
    if (self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);

    NSDictionary *eventBody = @{@"currentPosition": [NSNumber numberWithDouble:(position.doubleValue * 1000)],
                                @"duration" : [NSNumber numberWithInt:duration]};
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackPositionUpdated"
                                                  body:eventBody];
    NSDictionary *trackInfo = @{
                                MPMediaItemPropertyTitle: artistName,
                                MPMediaItemPropertyArtist: songTitle,
                                MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat: 1.0f],
                                MPMediaItemPropertyPlaybackDuration: [NSNumber numberWithFloat:duration],
                                MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
                                MPMediaItemPropertyArtwork: albumArt
                                };
    songInfo = trackInfo;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = trackInfo;
    NSLog(@"woke = %@", self);
}

- (NSTimeInterval)currentPlaybackTime
{
    if (self.player) {
        CMTime time = self.player.currentTime;
        if (CMTIME_IS_VALID(time)) {
            return time.value / time.timescale;
        }
    }
    return 0;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    
    if (object == self.player.currentItem && [keyPath isEqualToString:@"status"]) {
        // if current item status is ready to play && player has not begun playing
        if (self.player.currentItem.status == AVPlayerItemStatusReadyToPlay
            && CMTIME_COMPARE_INLINE(self.player.currentItem.currentTime, ==, kCMTimeZero)) {
            [self.player play];
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                            body: @{@"state": @"PLAYING" }];
            [self activateAudioSession];
            
        } else if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
            if (self.player.currentItem.error) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackError"
                                                                body: @{@"desc": self.player.currentItem.error.localizedDescription }];
            } else {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackError"
                                                                body: @{@"desc": @"Unknown error" }];
            }
        }
    } else if (object == self.player.currentItem && [keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        // check if player has paused && player has begun playing
        if (stalled && !self.player.rate && CMTIME_COMPARE_INLINE(self.player.currentItem.currentTime, >, kCMTimeZero)) {
            [self.player play];
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                            body: @{@"state": @"PLAYING" }];
            [self activateAudioSession];
            stalled = NO;
        }
    }
}

#pragma mark - Audio Session

- (void)itemDidPlayToEndTime:(NSNotification *)notification
{
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged" body: @{@"state": @"COMPLETED" }];
}

- (void)itemPlaybackStalled:(NSNotification *)notification
{
    stalled = true;
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged" body: @{@"state": @"PAUSED" }];
}

- (void)activateAudioSession
{
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (!error) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        if (!error) {
            
        } else {
            NSLog(@"Failed to set session category to playback: %@", error);
        }
    } else {
        NSLog(@"Failed to activate audio session: %@", error);
    }
}

- (void)deactivateAudioSession
{
    [[AVAudioSession sharedInstance] setActive:NO error:NULL];
}

- (void)registerAudioInterruptionNotifications
{
    // Register for audio interrupt notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAudioInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
}

- (void)unregisterAudioInterruptionNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionRouteChangeNotification
                                                  object:nil];
}

- (void)onAudioInterruption:(NSNotification *)notification
{
    // getting interruption type as int value from AVAudioSessionInterruptionTypeKey
    int interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
    int duration = 0;
    if (self.player && self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);
    switch (interruptionType)
    {
        case AVAudioSessionInterruptionTypeBegan:
            // if duration exists
            if (duration != 0) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged" body: @{@"state": @"PAUSED" }];
            }
            break;
            
        case AVAudioSessionInterruptionTypeEnded:
            // if duration exists && AVAudioSessionInterruptionOptionShouldResume (phone call)
            if (duration != 0 && [notification.userInfo[AVAudioSessionInterruptionOptionKey] intValue] == AVAudioSessionInterruptionOptionShouldResume) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PLAY" }];
            }
            break;
            
        default:
            NSLog(@"Audio Session Interruption Notification case default.");
            break;
    }
}


#pragma mark - Remote Control Events

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification
{
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    // when headphone was pulled (AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
    if (routeChangeReason == 2) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PAUSE" }];
    }
}

- (void)registerRemoteControlEvents
{
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    [commandCenter.playCommand addTargetWithHandler:^(MPRemoteCommandEvent * _Nonnull event) {
        int duration = 0;
        if (self.player && self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);
        // check if player is not nil & duration is not 0 (0 means player is not initialized or stopped)
        if (self.player && duration != 0) {
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PLAY" }];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }];
    
    [commandCenter.pauseCommand addTargetWithHandler:^(MPRemoteCommandEvent * _Nonnull event) {
        int duration = 0;
        if (self.player && self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);
        // check if player is not nil & duration is not 0 (0 means player is not initialized or stopped)
        if (self.player && duration != 0) {
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PAUSE" }];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }];
    
    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^(MPRemoteCommandEvent * _Nonnull event) {
        int duration = 0;
        if (self.player && self.player.currentItem) duration = CMTimeGetSeconds(self.player.currentItem.duration);
        // if duration exists 0 & audio is playing
        if (duration != 0 && self.player.rate) {
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PAUSE" }];
            return MPRemoteCommandHandlerStatusSuccess;
        } else if (duration != 0 && !self.player.rate) {
            [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged" body: @{@"action": @"PLAY" }];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }];

    [commandCenter.nextTrackCommand addTargetWithHandler:^(MPRemoteCommandEvent * _Nonnull event) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"SKIP_TO_NEXT" }];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.previousTrackCommand addTargetWithHandler:^(MPRemoteCommandEvent * _Nonnull event) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"SKIP_TO_PREVIOUS"}];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;
    commandCenter.stopCommand.enabled = NO;
}

- (void)unregisterRemoteControlEvents
{
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];
}

- (void)setNowPlayingInfo:(BOOL)isPlaying
{
    UIImage *artworkImage = nil;
    
    if (albumUrl != nil && [albumUrl isKindOfClass:[NSURL class]]) {
        artworkImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:albumUrl]];
    } else {
        artworkImage = _defaultArtwork;
    }
    
    if ([MPMediaItemArtwork respondsToSelector:@selector(initWithBoundsSize:requestHandler:)]) {
        albumArt = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size
                                                   requestHandler:^(CGSize size) {
            return artworkImage;
        }];
    } else {
        albumArt = [[MPMediaItemArtwork alloc] initWithImage:artworkImage];
    }
    
    songInfo = @{
                 MPMediaItemPropertyTitle: artistName,
                 MPMediaItemPropertyArtist: songTitle,
                 MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat:isPlaying ? 1.0f : 0.0],
                 MPMediaItemPropertyArtwork: albumArt,
                 };
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = songInfo;
}

@end

#pragma clang diagnostic pop

UIImage *_createColorImage(UIColor *color, CGRect imgBounds) {
    UIGraphicsBeginImageContextWithOptions(imgBounds.size, NO, 0);
    [color setFill];
    UIRectFill(imgBounds);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

