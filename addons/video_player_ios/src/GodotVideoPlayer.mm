#import "GodotVideoPlayer.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <UIKit/UIKit.h>

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/os/memory.h"
#include "core/string/ustring.h"

#include <cmath>

namespace {

static String string_from_ns(NSString *p_string) {
	if (p_string == nil) {
		return String();
	}
	return String::utf8([p_string UTF8String]);
}

static NSString *ns_string_from_godot(const String &p_string) {
	CharString utf8 = p_string.utf8();
	return [NSString stringWithUTF8String:utf8.get_data()];
}

static UIViewController *top_view_controller(UIViewController *p_controller) {
	UIViewController *controller = p_controller;
	while (controller.presentedViewController != nil && !controller.presentedViewController.isBeingDismissed) {
		controller = controller.presentedViewController;
	}
	return controller;
}

static UIViewController *active_root_view_controller() {
	UIApplication *application = [UIApplication sharedApplication];
	UIViewController *root = nil;

	if (@available(iOS 13.0, *)) {
		for (UIScene *scene in application.connectedScenes) {
			if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) {
				continue;
			}
			for (UIWindow *window in ((UIWindowScene *)scene).windows) {
				if (window.isKeyWindow && window.rootViewController != nil) {
					root = window.rootViewController;
					break;
				}
			}
			if (root != nil) {
				break;
			}
		}
	}

	if (root == nil) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		for (UIWindow *window in application.windows) {
			if (window.isKeyWindow && window.rootViewController != nil) {
				root = window.rootViewController;
				break;
			}
		}
#pragma clang diagnostic pop
	}

	return top_view_controller(root);
}

} // namespace

@interface GodotVideoPlayerIOSBridge : NSObject

@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerViewController *playerViewController;
@property(nonatomic, weak) AVPlayerItem *observedItem;
@property(nonatomic, assign) GodotVideoPlayerIOS *owner;
@property(nonatomic, assign) float volume;
@property(nonatomic, assign) BOOL looping;
@property(nonatomic, assign) float speedScale;

+ (instancetype)sharedBridge;
- (void)playPath:(NSString *)p_path allowSkip:(BOOL)p_allow_skip owner:(GodotVideoPlayerIOS *)p_owner;
- (void)pause;
- (void)resume;
- (void)seekTo:(float)p_seconds;
- (void)setVolume:(float)p_volume;
- (void)setLooping:(BOOL)p_looping;
- (void)setPlaybackSpeed:(float)p_speed;
- (BOOL)isPlaying;
- (float)duration;
- (float)currentPosition;
- (void)stop;

@end

@implementation GodotVideoPlayerIOSBridge

+ (instancetype)sharedBridge {
	static GodotVideoPlayerIOSBridge *bridge = nil;
	static dispatch_once_t once_token;
	 dispatch_once(&once_token, ^{
		bridge = [[GodotVideoPlayerIOSBridge alloc] init];
		bridge.volume = 1.0f;
		bridge.speedScale = 1.0f;
		bridge.looping = NO;
	});
	return bridge;
}

- (void)dealloc {
	[self removeObservers];
}

- (NSURL *)urlForPath:(NSString *)p_path {
	if ([p_path hasPrefix:@"http://"] || [p_path hasPrefix:@"https://"]) {
		return [NSURL URLWithString:p_path];
	}

	if ([p_path hasPrefix:@"res://"]) {
		NSString *resource = [p_path substringFromIndex:6];
		resource = [resource stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
		NSString *extension = resource.pathExtension;
		NSString *name = [resource stringByDeletingPathExtension];
		NSString *subdirectory = [resource stringByDeletingLastPathComponent];
		if ([subdirectory isEqualToString:@"."]) {
			subdirectory = nil;
		}
		NSURL *bundle_url = [[NSBundle mainBundle] URLForResource:name withExtension:extension subdirectory:subdirectory];
		if (bundle_url != nil) {
			return bundle_url;
		}
		NSString *bundle_path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:resource];
		if ([[NSFileManager defaultManager] fileExistsAtPath:bundle_path]) {
			return [NSURL fileURLWithPath:bundle_path];
		}
		return nil;
	}

	if ([p_path hasPrefix:@"file://"]) {
		return [NSURL URLWithString:p_path];
	}

	if ([[NSFileManager defaultManager] fileExistsAtPath:p_path]) {
		return [NSURL fileURLWithPath:p_path];
	}
	return nil;
}

- (void)removeObservers {
	if (self.observedItem != nil) {
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.observedItem];
		[center removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.observedItem];
		[center removeObserver:self name:AVPlayerItemNewErrorLogEntryNotification object:self.observedItem];
		self.observedItem = nil;
	}
}

- (void)notifyError:(NSString *)p_message {
	GodotVideoPlayerIOS *owner = self.owner;
	if (owner != nullptr) {
		owner->notify_video_error(string_from_ns(p_message));
	}
	[self stopInternal];
}

- (void)playPath:(NSString *)p_path allowSkip:(BOOL)p_allow_skip owner:(GodotVideoPlayerIOS *)p_owner {
	void (^operation)(void) = ^{
		[self stopInternal];
		self.owner = p_owner;

		NSURL *url = [self urlForPath:p_path];
		if (url == nil) {
			[self notifyError:[NSString stringWithFormat:@"Video file is not accessible: %@", p_path]];
			return;
		}

		AVPlayer *player = [AVPlayer playerWithURL:url];
		AVPlayerItem *item = player.currentItem;
		if (player == nil || item == nil) {
			[self notifyError:[NSString stringWithFormat:@"AVPlayer could not open: %@", p_path]];
			return;
		}

		self.player = player;
		self.player.volume = self.volume;
		self.player.rate = self.speedScale;
		self.observedItem = item;
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(playerDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
		[center addObserver:self selector:@selector(playerFailedToPlay:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
		[center addObserver:self selector:@selector(playerErrorLogChanged:) name:AVPlayerItemNewErrorLogEntryNotification object:item];

		UIViewController *root = active_root_view_controller();
		if (root == nil) {
			[self notifyError:@"No active iOS window is available for AVPlayer."];
			return;
		}

		AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
		controller.player = self.player;
		controller.showsPlaybackControls = p_allow_skip;
		controller.videoGravity = AVLayerVideoGravityResizeAspect;
		controller.allowsPictureInPicturePlayback = NO;
		self.playerViewController = controller;

		[root presentViewController:controller animated:YES completion:^{
			[self.player play];
		}];
	};

	if ([NSThread isMainThread]) {
		operation();
	} else {
		dispatch_async(dispatch_get_main_queue(), operation);
	}
}

- (void)pause {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.player pause];
	});
}

- (void)resume {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.player play];
		self.player.rate = self.speedScale;
	});
}

- (void)seekTo:(float)p_seconds {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.player == nil || !std::isfinite(p_seconds)) {
			return;
		}
		float seconds = MAX(0.0f, p_seconds);
		CMTime time = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
		[self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	});
}

- (void)setVolume:(float)p_volume {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.volume = MIN(1.0f, MAX(0.0f, p_volume));
		self.player.volume = self.volume;
	});
}

- (void)setLooping:(BOOL)p_looping {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.looping = p_looping;
	});
}

- (void)setPlaybackSpeed:(float)p_speed {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.speedScale = MAX(0.01f, p_speed);
		if (self.player != nil && self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
			self.player.rate = self.speedScale;
		}
	});
}

- (BOOL)isPlaying {
	__block BOOL playing = NO;
	void (^operation)(void) = ^{
		playing = self.player != nil && self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
	};
	if ([NSThread isMainThread]) {
		operation();
	} else {
		dispatch_sync(dispatch_get_main_queue(), operation);
	}
	return playing;
}

- (float)duration {
	__block float value = -1.0f;
	void (^operation)(void) = ^{
		if (self.player.currentItem == nil) {
			return;
		}
		Float64 seconds = CMTimeGetSeconds(self.player.currentItem.duration);
		if (std::isfinite(seconds) && seconds > 0.0) {
			value = (float)seconds;
		}
	};
	if ([NSThread isMainThread]) {
		operation();
	} else {
		dispatch_sync(dispatch_get_main_queue(), operation);
	}
	return value;
}

- (float)currentPosition {
	__block float value = 0.0f;
	void (^operation)(void) = ^{
		if (self.player == nil) {
			return;
		}
		Float64 seconds = CMTimeGetSeconds(self.player.currentTime);
		if (std::isfinite(seconds) && seconds > 0.0) {
			value = (float)seconds;
		}
	};
	if ([NSThread isMainThread]) {
		operation();
	} else {
		dispatch_sync(dispatch_get_main_queue(), operation);
	}
	return value;
}

- (void)playerDidFinishPlaying:(NSNotification *)p_notification {
	(void)p_notification;
	if (self.looping) {
		[self.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
			if (finished) {
				[self.player play];
				self.player.rate = self.speedScale;
			}
		}];
		return;
	}
	GodotVideoPlayerIOS *owner = self.owner;
	if (owner != nullptr) {
		owner->notify_video_completed();
	}
	[self stopInternal];
}

- (void)playerFailedToPlay:(NSNotification *)p_notification {
	AVPlayerItem *item = (AVPlayerItem *)p_notification.object;
	NSString *message = item.error.localizedDescription;
	if (message.length == 0) {
		message = @"AVPlayer failed to play the video.";
	}
	[self notifyError:message];
}

- (void)playerErrorLogChanged:(NSNotification *)p_notification {
	AVPlayerItem *item = (AVPlayerItem *)p_notification.object;
	AVPlayerItemErrorLogEvent *event = item.errorLog.events.lastObject;
	if (event.errorComment.length > 0) {
		[self notifyError:event.errorComment];
	}
}

- (void)stopInternal {
	[self removeObservers];
	[self.player pause];
	self.player = nil;

	AVPlayerViewController *controller = self.playerViewController;
	self.playerViewController = nil;
	self.owner = nullptr;
	if (controller.presentingViewController != nil) {
		[controller dismissViewControllerAnimated:YES completion:nil];
	}
}

- (void)stop {
	void (^operation)(void) = ^{
		[self stopInternal];
	};
	if ([NSThread isMainThread]) {
		operation();
	} else {
		dispatch_sync(dispatch_get_main_queue(), operation);
	}
}

@end

GodotVideoPlayerIOS *GodotVideoPlayerIOS::singleton = nullptr;

void GodotVideoPlayerIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("playVideo", "path", "allow_skip"), &GodotVideoPlayerIOS::play_video, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("pauseVideo"), &GodotVideoPlayerIOS::pause_video);
	ClassDB::bind_method(D_METHOD("resumeVideo"), &GodotVideoPlayerIOS::resume_video);
	ClassDB::bind_method(D_METHOD("seekTo", "seconds"), &GodotVideoPlayerIOS::seek_to);
	ClassDB::bind_method(D_METHOD("setVolume", "volume"), &GodotVideoPlayerIOS::set_volume);
	ClassDB::bind_method(D_METHOD("setLooping", "looping"), &GodotVideoPlayerIOS::set_looping);
	ClassDB::bind_method(D_METHOD("setPlaybackSpeed", "speed"), &GodotVideoPlayerIOS::set_playback_speed);
	ClassDB::bind_method(D_METHOD("isPlaying"), &GodotVideoPlayerIOS::is_playing);
	ClassDB::bind_method(D_METHOD("getDuration"), &GodotVideoPlayerIOS::get_duration);
	ClassDB::bind_method(D_METHOD("getCurrentPosition"), &GodotVideoPlayerIOS::get_current_position);
	ClassDB::bind_method(D_METHOD("stopVideo"), &GodotVideoPlayerIOS::stop_video);

	ADD_SIGNAL(MethodInfo("video_completed"));
	ADD_SIGNAL(MethodInfo("video_error", PropertyInfo(Variant::STRING, "message")));
}

GodotVideoPlayerIOS::GodotVideoPlayerIOS() {
	ERR_FAIL_COND(singleton != nullptr);
	singleton = this;
}

GodotVideoPlayerIOS::~GodotVideoPlayerIOS() {
	if (singleton == this) {
		stop_video();
		singleton = nullptr;
	}
}

GodotVideoPlayerIOS *GodotVideoPlayerIOS::get_singleton() {
	return singleton;
}

void GodotVideoPlayerIOS::destroy_singleton() {
	if (singleton != nullptr) {
		memdelete(singleton);
	}
}

void GodotVideoPlayerIOS::play_video(const String &p_path, bool p_allow_skip) {
	[[GodotVideoPlayerIOSBridge sharedBridge] playPath:ns_string_from_godot(p_path) allowSkip:p_allow_skip owner:this];
}

void GodotVideoPlayerIOS::pause_video() {
	[[GodotVideoPlayerIOSBridge sharedBridge] pause];
}

void GodotVideoPlayerIOS::resume_video() {
	[[GodotVideoPlayerIOSBridge sharedBridge] resume];
}

void GodotVideoPlayerIOS::seek_to(float p_seconds) {
	[[GodotVideoPlayerIOSBridge sharedBridge] seekTo:p_seconds];
}

void GodotVideoPlayerIOS::set_volume(float p_volume) {
	[[GodotVideoPlayerIOSBridge sharedBridge] setVolume:p_volume];
}

void GodotVideoPlayerIOS::set_looping(bool p_looping) {
	[[GodotVideoPlayerIOSBridge sharedBridge] setLooping:p_looping];
}

void GodotVideoPlayerIOS::set_playback_speed(float p_speed) {
	[[GodotVideoPlayerIOSBridge sharedBridge] setPlaybackSpeed:p_speed];
}

bool GodotVideoPlayerIOS::is_playing() const {
	return [[GodotVideoPlayerIOSBridge sharedBridge] isPlaying];
}

float GodotVideoPlayerIOS::get_duration() const {
	return [[GodotVideoPlayerIOSBridge sharedBridge] duration];
}

float GodotVideoPlayerIOS::get_current_position() const {
	return [[GodotVideoPlayerIOSBridge sharedBridge] currentPosition];
}

void GodotVideoPlayerIOS::stop_video() {
	[[GodotVideoPlayerIOSBridge sharedBridge] stop];
}

void GodotVideoPlayerIOS::notify_video_completed() {
	emit_signal(SNAME("video_completed"));
}

void GodotVideoPlayerIOS::notify_video_error(const String &p_message) {
	emit_signal(SNAME("video_error"), p_message);
}

extern "C" void register_avplayer_types() {
	if (GodotVideoPlayerIOS::get_singleton() != nullptr) {
		return;
	}
	// The iOS plugin entry point runs outside the usual module registration
	// path, so register the Object class explicitly before creating the
	// singleton. Without this, the bound methods and signals are never exposed
	// to GDScript through Engine.get_singleton("AVPlayer").
	if (!ClassDB::class_exists("GodotVideoPlayerIOS")) {
		ClassDB::register_class<GodotVideoPlayerIOS>();
	}
	GodotVideoPlayerIOS *player = memnew(GodotVideoPlayerIOS);
	Engine::get_singleton()->add_singleton(Engine::Singleton("AVPlayer", player));
}

extern "C" void unregister_avplayer_types() {
	GodotVideoPlayerIOS::destroy_singleton();
}
