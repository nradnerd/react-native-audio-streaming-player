package com.allthatseries.RNAudioPlayer;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import androidx.annotation.Nullable;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import android.media.MediaDescription;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.util.Log;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.util.HashMap;

public class RNAudioPlayerModule extends ReactContextBaseJavaModule implements ServiceConnection {
    ReactApplicationContext reactContext;

    private MediaController mMediaController;
    private AudioPlayerService mService;
    private HashMap<Integer, String> mStateMap = new HashMap<Integer, String>();

    public RNAudioPlayerModule(ReactApplicationContext reactContext) {
        super(reactContext);

        this.reactContext = reactContext;

        // Register receiver
        IntentFilter filter = new IntentFilter();
        filter.addAction("update-position-event");
        filter.addAction("change-playback-action-event");
        filter.addAction("change-playback-state-event");
        filter.addAction("playback-error-event");
        LocalBroadcastManager.getInstance(reactContext).registerReceiver(mLocalBroadcastReceiver, filter);

        mStateMap.put(PlaybackState.STATE_NONE,       "NONE");
        mStateMap.put(PlaybackState.STATE_STOPPED,    "STOPPED");
        mStateMap.put(PlaybackState.STATE_PAUSED,     "PAUSED");
        mStateMap.put(PlaybackState.STATE_PLAYING,    "PLAYING");
        mStateMap.put(PlaybackState.STATE_ERROR,      "ERROR");
        mStateMap.put(PlaybackState.STATE_BUFFERING,  "BUFFERING");
        mStateMap.put(12,                                   "COMPLETED");
    }

    private BroadcastReceiver mLocalBroadcastReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            WritableMap params = Arguments.createMap();

            switch(intent.getAction()) {
                case "update-position-event":
                    int nCurrentPosition = intent.getIntExtra("currentPosition", 0);
                    int nDuration = intent.getIntExtra("duration", 0);
                    params.putInt("currentPosition", nCurrentPosition);
                    params.putInt("duration", (nDuration / 1000));
                    sendEvent("onPlaybackPositionUpdated", params);
                    break;
                case "change-playback-action-event":
                    String strAction = intent.getStringExtra("action");
                    params.putString("action", strAction);
                    sendEvent("onPlaybackActionChanged", params);
                    break;
                case "change-playback-state-event":
                    int nState = intent.getIntExtra("state", 0);
                    if (mStateMap.containsKey(nState)) {
                        params.putString("state", mStateMap.get(nState));
                        sendEvent("onPlaybackStateChanged", params);
                    }
                    break;
                case "playback-error-event":
                    String strError = intent.getStringExtra("msg");
                    params.putString("msg", strError);
                    sendEvent("onPlaybackError", params);
                default:
                    break;
            }
        }
    };

    @Override
    public String getName() {
    return "RNAudioPlayer";
    }

    private void sendEvent(String eventName, @Nullable WritableMap params) {
        this.reactContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit(eventName, params);
    }

    @Override
    public void initialize() {
        super.initialize();

        try {
            Intent intent = new Intent(this.reactContext, AudioPlayerService.class);
            this.reactContext.startService(intent);
            this.reactContext.bindService(intent, this, Context.BIND_ADJUST_WITH_ACTIVITY);
        } catch (Exception e) {
            Log.e("ERROR", e.getMessage());
        }
    }

    @Override
    public void onServiceConnected(ComponentName name, IBinder service) {
        if (service instanceof AudioPlayerService.ServiceBinder) {

                mService = ((AudioPlayerService.ServiceBinder) service).getService();
                mMediaController = new MediaController(this.reactContext,
                        ((AudioPlayerService.ServiceBinder) service).getService().getMediaSessionToken());

        }
    }

    @Override
    public void onServiceDisconnected(ComponentName name) {
    }

    @ReactMethod
    public void play(String stream_url, ReadableMap metadata) {
        Bundle bundle = new Bundle();
        bundle.putString(MediaMetadata.METADATA_KEY_TITLE, metadata.getString("title"));
        bundle.putString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI, metadata.getString("album_art_uri"));
        bundle.putString(MediaMetadata.METADATA_KEY_ARTIST, metadata.getString("artist"));
    //    mMediaController.getTransportControls().playFromUri(Uri.parse(stream_url), bundle);
        MediaController.TransportControls controls = mMediaController.getTransportControls();
        bundle.putString("uri", stream_url);
        controls.sendCustomAction("PLAY_URI", bundle);

    }

    @ReactMethod
    public void pause() {
        mMediaController.getTransportControls().pause();
    }

    @ReactMethod
    public void resume() {
        mMediaController.getTransportControls().play();
    }

    @ReactMethod
    public void stop() {
        mMediaController.getTransportControls().stop();
    }

    @ReactMethod
    public void seekTo(int timeMillis) {
        mMediaController.getTransportControls().seekTo(timeMillis * 1000);
    }

    @ReactMethod
    public void isPlaying(Callback cb) {
        cb.invoke(mService.getPlayback().isPlaying());
    }

    @ReactMethod
    public void getDuration(Callback cb) {
        cb.invoke(mService.getPlayback().getDuration());
    }

    @ReactMethod
    public void getCurrentPosition(Callback cb) {
        cb.invoke(mService.getPlayback().getCurrentPosition());
    }
}