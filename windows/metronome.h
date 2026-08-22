#ifndef METRONOME_H_
#define METRONOME_H_

#include <vector>
#include <atomic>
#include <thread>
#include <cstdint>
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
//
#include <windows.h>
#include <mmsystem.h>
#include <cmath>
#include <mutex>
#include <condition_variable>
#include <string>
#include <flutter/event_sink.h>
#include <flutter/encodable_value.h>
class Metronome
{
public:
    Metronome(const std::vector<uint8_t> &mainFileBytes,
              const std::vector<uint8_t> &accentedFileBytes,
              int bpm, const std::vector<int> &accentPattern, double volume, int sampleRate);
    ~Metronome();

    void Play();
    void Pause();
    void Stop();
    void SetBPM(int bpm);
    void SetAccentPattern(const std::vector<int> &accentPattern);
    void SetVolume(double volume);
    void SetAudioFile(const std::vector<uint8_t> &mainFileBytes, const std::vector<uint8_t> &accentedSound);
    void EnableTickCallback(std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventSink);
    void EnableTempoRampCallback(std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventSink);
    void ConfigureTempoRamp(int startBpm, int targetBpm, int stepBpm, int measuresPerStep);
    void DisableTempoRamp();
    bool IsPlaying() const;
    void Destroy();
    int GetVolume() const;
    int audioBpm = 120;
    std::vector<int> accentPattern = {4};

private:
    static std::vector<int> NormalizeAccentPattern(const std::vector<int> &pattern);
    int GetTotalBeats() const;
    bool IsAccentBeat(int index) const;
    void StartMetronome();
    void InitializeAudio();
    void OnBufferDone();
    void PlaySound();
    std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventTickSink;
    std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventTempoRampSink;
    void CompleteRampMeasure();
    void ResetRamp();
    void EmitRampProgress();
    std::vector<int16_t> Metronome::byteArrayToShortArray(const std::vector<uint8_t> &byteArray);
    std::vector<int16_t> Metronome::generateBuffer();
    static void CALLBACK WaveOutProc(HWAVEOUT hwo, UINT uMsg, DWORD_PTR dwInstance, DWORD_PTR dwParam1, DWORD_PTR dwParam2);
    HWAVEOUT hWaveOut;
    size_t playCursor;
    size_t writeCursor;
    std::mutex bufferMutex;
    std::condition_variable bufferCV;
    std::mutex paramMutex;
    int currentTick = 0;
    int rampBeatInMeasure = 0;
    bool rampEnabled = false;
    std::string rampStatus = "idle";
    int rampStartBpm = 0;
    int rampTargetBpm = 0;
    int rampStepBpm = 0;
    int rampMeasuresPerStep = 0;
    int rampStageIndex = 0;
    int rampCompletedMeasures = 0;
    //
    std::vector<int16_t> audioBufferTemp;
    std::vector<int16_t> audioBuffer;
    std::vector<int16_t> mainSound;
    std::vector<int16_t> accentedSound;
    int sampleRate = 44100;
    int beatLength = 0;
    double audioVolume = 1.0;
    std::atomic<bool> playing{false};
    std::thread metronomeThread;
};

#endif // METRONOME_H_
