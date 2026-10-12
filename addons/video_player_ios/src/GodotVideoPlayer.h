#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"

/**
 * Godot-facing singleton for the iOS AVPlayer bridge.
 *
 * AVFoundation objects live in the Objective-C++ implementation so this
 * header can also be included by the Godot registration code.
 */
class GodotVideoPlayerIOS : public Object {
	GDCLASS(GodotVideoPlayerIOS, Object);

	static GodotVideoPlayerIOS *singleton;
	static void _bind_methods();

public:
	static GodotVideoPlayerIOS *get_singleton();
	static void destroy_singleton();

	void play_video(const String &p_path, bool p_allow_skip = true);
	void pause_video();
	void resume_video();
	void seek_to(float p_seconds);
	void set_volume(float p_volume);
	void set_looping(bool p_looping);
	void set_playback_speed(float p_speed);
	bool is_playing() const;
	float get_duration() const;
	float get_current_position() const;
	void stop_video();

	// Called by the Objective-C bridge on the main thread.
	void notify_video_completed();
	void notify_video_error(const String &p_message);

	GodotVideoPlayerIOS();
	~GodotVideoPlayerIOS();
};

// Entry points referenced by the .gdip file.
extern "C" void register_avplayer_types();
extern "C" void unregister_avplayer_types();
