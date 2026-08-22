#include "metronome.h"
#include <cmath>
#include <iostream>
#include <vector>
#include <cstdint>
#include <stdexcept>
#include <cstring>
#include <thread>
#include <atomic>
#include <chrono>
#include <string>

Metronome::Metronome(const std::vector<uint8_t> &mainFileBytes,
                     const std::vector<uint8_t> &accentedFileBytes,
                     int bpm, const std::vector<int> &accentPattern, double volume, int sampleRate)
    : audioBpm(bpm), accentPattern(NormalizeAccentPattern(accentPattern)), audioVolume(volume), sampleRate(sampleRate)
{
    if (mainFileBytes.empty())
    {
        throw std::invalid_argument("Main sound file cannot be empty");
    }

    mainSound = byteArrayToShortArray(mainFileBytes);
    accentedSound = accentedFileBytes.empty() ? mainSound : byteArrayToShortArray(accentedFileBytes);

    InitializeAudio();
    audioBuffer = generateBuffer();
}

Metronome::~Metronome()
{
    Destroy();
}

void Metronome::Play()
{
    if (!playing.exchange(true))
    {
        audioBuffer = generateBuffer();
        if (hWaveOut)
        {
            waveOutRestart(hWaveOut);
        }
        metronomeThread = std::thread(&Metronome::StartMetronome, this);
        if (rampEnabled && rampStatus != "completed")
        {
            rampStatus = "running";
            EmitRampProgress();
        }
    }
}

void Metronome::Pause()
{
    if (playing.exchange(false))
    {
        if (hWaveOut)
        {
            // waveOutPause(hWaveOut);
            waveOutBreakLoop(hWaveOut);
            // waveOutWrite(hWaveOut, nullptr, 0);
        }
        currentTick = 0;
        rampBeatInMeasure = 0;
        writeCursor = playCursor = 0;
        if (metronomeThread.joinable())
        {
            metronomeThread.join();
        }
        if (rampEnabled && rampStatus == "running")
        {
            rampStatus = "paused";
            EmitRampProgress();
        }
    }
}

void Metronome::Stop()
{
    if (playing.exchange(false))
    {
        if (hWaveOut)
        {
            waveOutReset(hWaveOut);
        }

        if (metronomeThread.joinable())
        {
            metronomeThread.join();
        }
    }
    if (rampEnabled)
    {
        ResetRamp();
    }
}
void Metronome::SetBPM(int bpm)
{
    if (rampEnabled)
    {
        DisableTempoRamp();
    }
    if (audioBpm != bpm)
    {
        bool wasPlaying = IsPlaying();
        if (wasPlaying)
        {
            Pause();
        }
        audioBpm = bpm;
        if (wasPlaying)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Play();
        }
    }
}
std::vector<int> Metronome::NormalizeAccentPattern(const std::vector<int> &pattern)
{
    if (pattern.empty())
        return {4};
    for (int group : pattern)
        if (group < 1)
            return {4};
    return pattern;
}

int Metronome::GetTotalBeats() const
{
    int total = 0;
    for (int group : accentPattern)
        total += group;
    return total;
}

bool Metronome::IsAccentBeat(int index) const
{
    int position = 0;
    for (int group : accentPattern)
    {
        if (index == position)
            return true;
        position += group;
    }
    return false;
}

void Metronome::SetAccentPattern(const std::vector<int> &newPattern)
{
    const std::vector<int> normalized = NormalizeAccentPattern(newPattern);
    if (accentPattern != normalized)
    {
        bool wasPlaying = IsPlaying();
        if (wasPlaying)
            Pause();
        accentPattern = normalized;
        if (wasPlaying)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Play();
        }
    }
}

void Metronome::SetVolume(double volume)
{
    if (volume < 0.0 || volume > 1.0)
    {
        throw std::invalid_argument("Volume must be between 0.0 and 1.0");
    }

    audioVolume = volume;
    if (hWaveOut)
    {
        DWORD vol = static_cast<DWORD>(0xFFFF * volume);
        waveOutSetVolume(hWaveOut, vol | (vol << 16));
    }
}

void Metronome::SetAudioFile(const std::vector<uint8_t> &mainFileBytes,
                             const std::vector<uint8_t> &accentedFileBytes)
{

    if (!mainFileBytes.empty() || !accentedFileBytes.empty())
    {
        bool wasPlaying = IsPlaying();
        if (wasPlaying)
        {
            Pause();
        }
        if (!mainFileBytes.empty())
        {
            mainSound = byteArrayToShortArray(mainFileBytes);
        }
        if (!accentedFileBytes.empty())
        {
            accentedSound = byteArrayToShortArray(accentedFileBytes);
        }

        if (wasPlaying)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Play();
        }
    }
}
int Metronome::GetVolume() const
{
    return static_cast<int>(audioVolume * 100);
}
bool Metronome::IsPlaying() const
{
    return playing.load();
}
void Metronome::EnableTickCallback(std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventSink)
{
    this->eventTickSink = eventSink;
}
void Metronome::EnableTempoRampCallback(std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> eventSink)
{
    eventTempoRampSink = eventSink;
    if (rampEnabled)
    {
        EmitRampProgress();
    }
}
void Metronome::ConfigureTempoRamp(int startBpm, int targetBpm, int stepBpm, int measuresPerStep)
{
    if (IsPlaying())
    {
        throw std::logic_error("Pause or stop before configuring a tempo ramp");
    }
    rampEnabled = true;
    rampStartBpm = startBpm;
    rampTargetBpm = targetBpm;
    rampStepBpm = stepBpm;
    rampMeasuresPerStep = measuresPerStep;
    ResetRamp();
}
void Metronome::DisableTempoRamp()
{
    rampEnabled = false;
    rampStatus = "idle";
    rampStageIndex = 0;
    rampCompletedMeasures = 0;
    EmitRampProgress();
}
std::vector<int16_t> Metronome::byteArrayToShortArray(const std::vector<uint8_t> &byteArray)
{
    if (byteArray.empty() || byteArray.size() % 2 != 0)
    {
        throw std::invalid_argument("Invalid byte array length for PCM_16BIT");
    }

    std::vector<int16_t> shortArray(byteArray.size() / 2);
    std::memcpy(shortArray.data(), byteArray.data(), byteArray.size());
    return shortArray;
}

std::vector<int16_t> Metronome::generateBuffer()
{
    int newBeatLength = static_cast<int>(sampleRate * 60.0 / audioBpm);
    std::vector<int16_t> bufferBar;
    const int beats = GetTotalBeats();
    if (beats < 2)
    {
        bufferBar.resize(newBeatLength, 0);
        std::copy_n(mainSound.begin(), min(newBeatLength, static_cast<int>(mainSound.size())), bufferBar.begin());
    }
    else
    {
        bufferBar.resize(newBeatLength * beats, 0);
        for (int i = 0; i < beats; i++)
        {
            const std::vector<int16_t> &sound = IsAccentBeat(i) ? accentedSound : mainSound;
            int copyLength = min(newBeatLength, static_cast<int>(sound.size()));
            std::copy_n(sound.begin(), copyLength, bufferBar.begin() + i * newBeatLength);
        }
    }

    beatLength = newBeatLength;

    return bufferBar;
}

void Metronome::InitializeAudio()
{
    WAVEFORMATEX wfx = {0};
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 1;
    wfx.nSamplesPerSec = sampleRate;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = 2;
    wfx.nAvgBytesPerSec = sampleRate * 2;

    MMRESULT result = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx,
                                  reinterpret_cast<DWORD_PTR>(&Metronome::WaveOutProc),
                                  reinterpret_cast<DWORD_PTR>(this),
                                  CALLBACK_FUNCTION);

    if (result != MMSYSERR_NOERROR)
    {
        throw std::runtime_error("Failed to initialize audio device. Error: " + std::to_string(result));
    }
    SetVolume(audioVolume);
}

void CALLBACK Metronome::WaveOutProc(HWAVEOUT hwo, UINT uMsg,
                                     DWORD_PTR dwInstance,
                                     DWORD_PTR dwParam1,
                                     DWORD_PTR dwParam2)
{
    if (uMsg == WOM_DONE)
    {
        WAVEHDR *hdr = reinterpret_cast<WAVEHDR *>(dwParam1);
        Metronome *metronome = reinterpret_cast<Metronome *>(dwInstance);

        if (hdr)
        {
            waveOutUnprepareHeader(hwo, hdr, sizeof(WAVEHDR));
            delete[] hdr->lpData;
            delete hdr;
        }

        if (metronome && metronome->playing.load())
        {
            metronome->OnBufferDone();
        }
    }
}
void Metronome::OnBufferDone()
{
    std::lock_guard<std::mutex> lock(bufferMutex);
    playCursor += beatLength;
    //
    if (eventTickSink != nullptr)
    {
        const int beats = GetTotalBeats();
        if (beats < 2)
        {
            currentTick = 0;
        }
        else
        {
            currentTick++;
            if (currentTick >= beats)
                currentTick = 0;
        }
        eventTickSink->Success(flutter::EncodableValue(currentTick));
    }
    rampBeatInMeasure = (rampBeatInMeasure + 1) % std::max(1, GetTotalBeats());
    if (rampBeatInMeasure == 0)
    {
        CompleteRampMeasure();
    }
    bufferCV.notify_one();
}

void Metronome::CompleteRampMeasure()
{
    if (!rampEnabled || rampStatus != "running")
        return;
    rampCompletedMeasures++;
    if (rampCompletedMeasures >= rampMeasuresPerStep)
    {
        std::lock_guard<std::mutex> lock(paramMutex);
        rampCompletedMeasures = 0;
        audioBpm = min(audioBpm + rampStepBpm, rampTargetBpm);
        rampStageIndex++;
        audioBuffer = generateBuffer();
        writeCursor = playCursor = 0;
        if (audioBpm >= rampTargetBpm)
            rampStatus = "completed";
    }
    EmitRampProgress();
}

void Metronome::ResetRamp()
{
    audioBpm = rampStartBpm;
    rampStatus = "armed";
    rampStageIndex = 0;
    rampCompletedMeasures = 0;
    rampBeatInMeasure = 0;
    audioBuffer = generateBuffer();
    writeCursor = playCursor = 0;
    EmitRampProgress();
}

void Metronome::EmitRampProgress()
{
    if (!eventTempoRampSink)
        return;
    int totalStages = rampEnabled
                          ? ((rampTargetBpm - rampStartBpm + rampStepBpm - 1) / rampStepBpm) + 1
                          : 0;
    flutter::EncodableMap progress;
    progress[flutter::EncodableValue("status")] = flutter::EncodableValue(rampStatus);
    progress[flutter::EncodableValue("currentBpm")] = flutter::EncodableValue(rampEnabled ? audioBpm : 0);
    progress[flutter::EncodableValue("stageIndex")] = flutter::EncodableValue(rampStageIndex);
    progress[flutter::EncodableValue("completedMeasures")] = flutter::EncodableValue(rampCompletedMeasures);
    progress[flutter::EncodableValue("totalStages")] = flutter::EncodableValue(totalStages);
    eventTempoRampSink->Success(flutter::EncodableValue(progress));
}
void Metronome::PlaySound()
{
    if (!IsPlaying())
        return;

    //
    WAVEHDR *hdr = new WAVEHDR{0};
    int16_t *buffer = new int16_t[beatLength];

    //
    size_t currentWriteCursor;
    {
        std::lock_guard<std::mutex> lock(paramMutex);
        currentWriteCursor = writeCursor;

        //
        size_t startPos = currentWriteCursor % audioBuffer.size();
        size_t copySize = min(beatLength,
                              static_cast<int>(audioBuffer.size() - startPos));

        std::copy(audioBuffer.begin() + startPos,
                  audioBuffer.begin() + startPos + copySize,
                  buffer);

        if (copySize < beatLength)
        {
            std::copy(audioBuffer.begin(),
                      audioBuffer.begin() + (beatLength - copySize),
                      buffer + copySize);
        }

        writeCursor += beatLength;
    }

    hdr->lpData = reinterpret_cast<char *>(buffer);
    hdr->dwBufferLength = beatLength * sizeof(int16_t);

    //
    MMRESULT result = waveOutPrepareHeader(hWaveOut, hdr, sizeof(WAVEHDR));
    if (result != MMSYSERR_NOERROR)
    {
        delete[] buffer;
        delete hdr;
        return;
    }

    result = waveOutWrite(hWaveOut, hdr, sizeof(WAVEHDR));
    if (result != MMSYSERR_NOERROR)
    {
        waveOutUnprepareHeader(hWaveOut, hdr, sizeof(WAVEHDR));
        delete[] buffer;
        delete hdr;
        return;
    }

    //
    const int beatMs = 60000 / audioBpm;
    auto sleepUntil = std::chrono::steady_clock::now() +
                      std::chrono::milliseconds(beatMs);
    std::this_thread::sleep_until(sleepUntil);
}

void Metronome::StartMetronome()
{
    try
    {
        while (playing.load())
        {
            PlaySound();
        }
    }
    catch (...)
    {
        playing.store(false);
        throw;
    }
}
void Metronome::Destroy()
{
    Stop();
    if (hWaveOut)
    {
        waveOutClose(hWaveOut);
        hWaveOut = nullptr;
    }
}
