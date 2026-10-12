package org.godotengine.plugin.android.videoplayer;

import android.app.Activity;
import android.net.Uri;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.PlayerView;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.util.HashSet;
import java.util.Set;

/**
 * Android Native Video Player Plugin for Godot 4.
 * Uses Android Media3 ExoPlayer for full hardware acceleration.
 */
public class GodotVideoPlayer extends GodotPlugin {
    private static final String PLUGIN_NAME = "GodotVideoPlayer";
    private ExoPlayer player;
    private PlayerView playerView;
    private FrameLayout containerView;
    private float pendingVolume = 1.0f;
    private boolean pendingLooping = false;
    private float pendingPlaybackSpeed = 1.0f;

    public GodotVideoPlayer(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("video_completed"));
        signals.add(new SignalInfo("video_error", String.class));
        signals.add(new SignalInfo("video_started"));
        signals.add(new SignalInfo("video_paused"));
        signals.add(new SignalInfo("video_resumed"));
        return signals;
    }

    @Nullable
    @Override
    public View onMainCreate(Activity activity) {
        containerView = new FrameLayout(activity);
        containerView.setVisibility(View.GONE);
        return containerView;
    }

    @UsedByGodot
    public void playVideo(final String path, final boolean allowSkip) {
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal("video_error", "Activity is null");
            return;
        }

        activity.runOnUiThread(() -> {
            try {
                if (path.startsWith("res://")) {
                    emitSignal("video_error", "Packed res:// videos must be copied to a filesystem path before native Android playback.");
                    return;
                }
                if (player == null) {
                    player = new ExoPlayer.Builder(activity).build();
                    playerView = new PlayerView(activity);
                    playerView.setUseController(allowSkip);
                    playerView.setPlayer(player);

                    player.addListener(new Player.Listener() {
                        @Override
                        public void onPlaybackStateChanged(int playbackState) {
                            if (playbackState == Player.STATE_ENDED) {
                                stopVideo();
                                emitSignal("video_completed");
                            } else if (playbackState == Player.STATE_READY) {
                                emitSignal("video_started");
                            }
                        }

                        @Override
                        public void onPlayerError(@NonNull PlaybackException error) {
                            stopVideo();
                            emitSignal("video_error", error.getMessage() != null ? error.getMessage() : "Unknown playback error");
                        }

                        @Override
                        public void onIsPlayingChanged(boolean isPlaying) {
                            if (isPlaying) {
                                emitSignal("video_resumed");
                            } else {
                                emitSignal("video_paused");
                            }
                        }
                    });

                    if (containerView != null) {
                        containerView.removeAllViews();
                        containerView.addView(playerView, new FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT
                        ));
                    }
                }

                Uri uri;
                if (path.startsWith("http://") || path.startsWith("https://") || path.startsWith("content://")) {
                    uri = Uri.parse(path);
                } else {
                    uri = Uri.fromFile(new File(path));
                }

                MediaItem mediaItem = MediaItem.fromUri(uri);
                player.setMediaItem(mediaItem);
                player.setVolume(pendingVolume);
                player.setRepeatMode(pendingLooping ? Player.REPEAT_MODE_ONE : Player.REPEAT_MODE_OFF);
                player.setPlaybackParameters(new PlaybackParameters(pendingPlaybackSpeed, 1.0f));
                player.prepare();
                player.play();

                if (containerView != null) {
                    containerView.setVisibility(View.VISIBLE);
                    containerView.bringToFront();
                }
            } catch (Exception e) {
                emitSignal("video_error", e.getMessage() != null ? e.getMessage() : "Unknown playback error");
            }
        });
    }

    @UsedByGodot
    public void pauseVideo() {
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null && player.isPlaying()) {
                player.pause();
            }
        });
    }

    @UsedByGodot
    public void resumeVideo() {
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null && !player.isPlaying()) {
                player.play();
            }
        });
    }

    @UsedByGodot
    public void seekTo(final float seconds) {
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null) {
                long posMs = (long) (seconds * 1000.0f);
                player.seekTo(posMs);
            }
        });
    }

    @UsedByGodot
    public void setVolume(final float volume) {
        pendingVolume = Math.max(0.0f, Math.min(1.0f, volume));
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null) {
                player.setVolume(pendingVolume);
            }
        });
    }

    @UsedByGodot
    public void setLooping(final boolean looping) {
        pendingLooping = looping;
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null) {
                player.setRepeatMode(pendingLooping ? Player.REPEAT_MODE_ONE : Player.REPEAT_MODE_OFF);
            }
        });
    }

    @UsedByGodot
    public void setPlaybackSpeed(final float speed) {
        pendingPlaybackSpeed = Math.max(0.01f, speed);
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (player != null) {
                player.setPlaybackParameters(new PlaybackParameters(pendingPlaybackSpeed, 1.0f));
            }
        });
    }

    @UsedByGodot
    public boolean isPlaying() {
        return player != null && player.isPlaying();
    }

    @UsedByGodot
    public float getDuration() {
        if (player == null) return -1.0f;
        long dur = player.getDuration();
        return dur > 0 ? (float) dur / 1000.0f : -1.0f;
    }

    @UsedByGodot
    public float getCurrentPosition() {
        if (player == null) return 0.0f;
        long pos = player.getCurrentPosition();
        return pos > 0 ? (float) pos / 1000.0f : 0.0f;
    }

    @UsedByGodot
    public void stopVideo() {
        final Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() -> {
            if (player != null) {
                player.stop();
                player.release();
                player = null;
            }
            if (containerView != null) {
                containerView.setVisibility(View.GONE);
                containerView.removeAllViews();
            }
        });
    }

    @Override
    public void onMainDestroy() {
        stopVideo();
        super.onMainDestroy();
    }
}
