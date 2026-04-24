package com.sumsg.metronome;

import static android.media.AudioTrack.PLAYSTATE_PLAYING;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Build;

import android.media.AudioAttributes;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

import io.flutter.plugin.common.EventChannel;

public class Metronome {
    private final Object mLock = new Object();
    private final AudioTrack audioTrack;
    private short[] mainSound;
    private short[] accentedSound;
    private short[] audioBuffer;
    private final int SAMPLE_RATE;
    public int audioBpm;
    /// Group sizes per bar; first beat of each group uses the accented sound.
    public int[] accentPattern;
    public float audioVolume;
    private boolean updated = false;
    private EventChannel.EventSink eventTickSink;
    private int currentTick = 0;

    @SuppressWarnings("deprecation")
    public Metronome(byte[] mainFileBytes, byte[] accentedFileBytes, int bpm, int[] accentPattern, float volume,
            int sampleRate) {
        SAMPLE_RATE = sampleRate;
        audioBpm = bpm;
        audioVolume = volume;
        this.accentPattern = normalizeAccentPattern(accentPattern);
        mainSound = byteArrayToShortArray(mainFileBytes);
        if (accentedFileBytes.length == 0) {
            accentedSound = mainSound;
        } else {
            accentedSound = byteArrayToShortArray(accentedFileBytes);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioFormat audioFormat = new AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build();
            AudioAttributes audioAttributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            audioTrack = new AudioTrack.Builder()
                    .setAudioAttributes(audioAttributes)
                    .setAudioFormat(audioFormat)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build();
        } else {
            audioTrack = new AudioTrack(AudioManager.STREAM_MUSIC, SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, SAMPLE_RATE, AudioTrack.MODE_STREAM);
        }
        setVolume(volume);
    }

    private static int[] normalizeAccentPattern(int[] pattern) {
        if (pattern == null || pattern.length == 0) {
            return new int[]{4};
        }
        for (int g : pattern) {
            if (g < 1) {
                return new int[]{4};
            }
        }
        return Arrays.copyOf(pattern, pattern.length);
    }

    private int getTotalBeats() {
        int sum = 0;
        for (int g : accentPattern) {
            sum += g;
        }
        return sum;
    }

    private boolean isAccentBeat(int index) {
        int pos = 0;
        for (int group : accentPattern) {
            if (index == pos) {
                return true;
            }
            pos += group;
        }
        return false;
    }

    public void play() {
        if (!isPlaying()) {
            updated = true;
            onTick();
            if (eventTickSink != null) {
                eventTickSink.success(0);
            }
            audioTrack.play();
            startMetronome();
        }
    }

    public void pause() {
        audioTrack.pause();
    }

    public void stop() {
        audioTrack.flush();
        audioTrack.stop();
    }

    public void setBPM(int bpm) {
        if (bpm != audioBpm) {
            audioBpm = bpm;
            if (isPlaying()) {
                pause();
                play();
            }
        }
    }

    public void setAccentPattern(int[] pattern) {
        int[] normalized = normalizeAccentPattern(pattern);
        if (!Arrays.equals(accentPattern, normalized)) {
            accentPattern = normalized;
            if (isPlaying()) {
                pause();
                play();
            }
        }
    }

    public void setAudioFile(byte[] mainFileBytes, byte[] accentedFileBytes) {
        if (mainFileBytes.length > 0) {
            mainSound = byteArrayToShortArray(mainFileBytes);
        }
        if (accentedFileBytes.length > 0) {
            accentedSound = byteArrayToShortArray(accentedFileBytes);
        }
        if (mainFileBytes.length > 0 || accentedFileBytes.length > 0) {
            if (isPlaying()) {
                pause();
                play();
            }
        }
    }

    @SuppressWarnings("deprecation")
    public void setVolume(float volume) {
        audioVolume = volume;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            audioTrack.setVolume(volume);
        } else {
            audioTrack.setStereoVolume(volume, volume);
        }
    }

    public boolean isPlaying() {
        return audioTrack.getPlayState() == PLAYSTATE_PLAYING;
    }

    public void enableTickCallback(EventChannel.EventSink _eventTickSink) {
        eventTickSink = _eventTickSink;
    }

    private short[] byteArrayToShortArray(byte[] byteArray) {
        if (byteArray == null || byteArray.length % 2 != 0) {
            throw new IllegalArgumentException("Invalid byte array length for PCM_16BIT");
        }
        short[] shortArray = new short[byteArray.length / 2];
        ByteBuffer.wrap(byteArray).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shortArray);
        return shortArray;
    }

    private short[] generateBuffer() {
        currentTick = 0;
        int framesPerBeat = (int) (SAMPLE_RATE * 60 / (float) audioBpm);
        short[] bufferBar;
        int beats = getTotalBeats();
        if (beats < 2) {
            bufferBar = new short[framesPerBeat];
            int soundLength = Math.min(framesPerBeat, mainSound.length);
            System.arraycopy(mainSound, 0, bufferBar, 0, soundLength);
        } else {
            int bufferSize = framesPerBeat * beats;
            bufferBar = new short[bufferSize];
            for (int i = 0; i < beats; i++) {
                short[] sound = isAccentBeat(i) ? accentedSound : mainSound;
                int soundLength = Math.min(framesPerBeat, sound.length);
                System.arraycopy(sound, 0, bufferBar, i * framesPerBeat, soundLength);
            }
        }
        updated = false;
        return bufferBar;
    }

    void onTick() {
        if (eventTickSink == null)
            return;
        int framesPerBeat = (int) ((SAMPLE_RATE * 60.0) / audioBpm);
        audioTrack.setPositionNotificationPeriod(framesPerBeat);
        audioTrack.setPlaybackPositionUpdateListener(new AudioTrack.OnPlaybackPositionUpdateListener() {
            @Override
            public void onMarkerReached(AudioTrack track) {
            }

            @Override
            public void onPeriodicNotification(AudioTrack track) {
                if (!updated) {
                    int beats = getTotalBeats();
                    if (beats < 2) {
                        currentTick = 0;
                    } else {
                        currentTick++;
                        if (currentTick >= beats)
                            currentTick = 0;
                    }
                    eventTickSink.success(currentTick);
                }
            }
        });
    }

    private void startMetronome() {
        new Thread(() -> {
            while (isPlaying()) {
                synchronized (mLock) {
                    if (!isPlaying()) {
                        return;
                    }
                    if (updated) {
                        audioBuffer = generateBuffer();
                    } else {
                        audioTrack.write(audioBuffer, 0, audioBuffer.length);
                    }
                }
            }
        }).start();
    }

    public void destroy() {
        stop();
        audioTrack.release();
    }
}
