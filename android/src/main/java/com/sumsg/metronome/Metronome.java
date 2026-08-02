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
    private short[] subdivisionSound;
    private short[] audioBuffer;
    private final int SAMPLE_RATE;
    public int audioBpm;
    /// Group sizes per bar; first beat of each group uses the accented sound.
    public int[] accentPattern;
    /// Clicks per beat (1=quarter, 2=8th, 3=triplet, 6=sextuplet).
    public int subdivision;
    /// Volume multiplier for subdivision clicks (0.0-1.0).
    public float subdivisionVolume;
    public float audioVolume;
    private boolean updated = false;
    private EventChannel.EventSink eventTickSink;
    private int currentTick = 0;

    @SuppressWarnings("deprecation")
    public Metronome(byte[] mainFileBytes, byte[] accentedFileBytes, byte[] subdivisionFileBytes, int bpm, int[] accentPattern, int subdivision, float subdivisionVolume, float volume,
            int sampleRate) {
        SAMPLE_RATE = sampleRate;
        audioBpm = bpm;
        audioVolume = volume;
        this.accentPattern = normalizeAccentPattern(accentPattern);
        this.subdivision = Math.max(1, subdivision);
        this.subdivisionVolume = subdivisionVolume;
        mainSound = byteArrayToShortArray(mainFileBytes);
        if (accentedFileBytes.length == 0) {
            accentedSound = mainSound;
        } else {
            accentedSound = byteArrayToShortArray(accentedFileBytes);
        }
        if (subdivisionFileBytes.length == 0) {
            subdivisionSound = mainSound;
        } else {
            subdivisionSound = byteArrayToShortArray(subdivisionFileBytes);
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

    private int getTotalSubTicks() {
        return getTotalBeats() * subdivision;
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

    public void setSubdivision(int newSubdivision) {
        int normalized = Math.max(1, newSubdivision);
        if (subdivision != normalized) {
            subdivision = normalized;
            if (isPlaying()) {
                pause();
                play();
            }
        }
    }

    public void setSubdivisionVolume(float newSubdivisionVolume) {
        subdivisionVolume = newSubdivisionVolume;
        if (isPlaying()) {
            pause();
            play();
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
        int framesPerSubBeat = (int) (SAMPLE_RATE * 60 / ((float) audioBpm * subdivision));
        int totalSlots = getTotalSubTicks();
        totalSlots = Math.max(1, totalSlots);
        int bufferSize = framesPerSubBeat * totalSlots;
        short[] bufferBar = new short[bufferSize];

        // Pre-scale subdivision sound
        short[] scaledSubdivision = new short[subdivisionSound.length];
        for (int j = 0; j < subdivisionSound.length; j++) {
            scaledSubdivision[j] = (short) (subdivisionSound[j] * subdivisionVolume);
        }

        for (int tick = 0; tick < totalSlots; tick++) {
            boolean isDownbeat = (tick % subdivision) == 0;
            int beatIndex = tick / subdivision;
            short[] sound;
            if (isDownbeat) {
                sound = isAccentBeat(beatIndex) ? accentedSound : mainSound;
            } else {
                sound = scaledSubdivision;
            }
            int soundLength = Math.min(framesPerSubBeat, sound.length);
            System.arraycopy(sound, 0, bufferBar, tick * framesPerSubBeat, soundLength);
        }
        updated = false;
        return bufferBar;
    }

    void onTick() {
        if (eventTickSink == null)
            return;
        int framesPerSubBeat = (int) ((SAMPLE_RATE * 60.0) / (audioBpm * subdivision));
        audioTrack.setPositionNotificationPeriod(framesPerSubBeat);
        audioTrack.setPlaybackPositionUpdateListener(new AudioTrack.OnPlaybackPositionUpdateListener() {
            @Override
            public void onMarkerReached(AudioTrack track) {
            }

            @Override
            public void onPeriodicNotification(AudioTrack track) {
                if (!updated) {
                    int totalSlots = getTotalSubTicks();
                    if (totalSlots < 2) {
                        currentTick = 0;
                    } else {
                        currentTick++;
                        if (currentTick >= totalSlots)
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
