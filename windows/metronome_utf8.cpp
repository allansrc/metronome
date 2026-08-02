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

std::vector<int> Metronome::NormalizeAccentPattern(const std::vector<int> &pattern)
{
    if (pattern.empty())
        return {4};
    for (int g : pattern)
    {
        if (g < 1)
            return {4};
    }
    return pattern;
}

int Metronome::GetTotalBeats() const
{
    int sum = 0;
    for (int g : accentPattern)
        sum += g;
    return sum;
}

bool Metronome::IsAccentBeat(int index) const
{
    int pos = 0;
    for (int group : accentPattern)
    {
        if (index == pos)
            return true;
        pos += group;
    }
    return false;
}

Metronome::Metronome(const std::vector<uint8_t> &mainFileBytes,
                     const std::vector<uint8_t> &accentedFileBytes,
                     const std::vector<uint8_t> &subdivisionFileBytes,
                     int bpm, const std::vector<int> &accentPatternIn, int subdivision, double subdivisionVolume, double volume, int sampleRate)
    : audioBpm(bpm), accentPattern(NormalizeAccentPattern(accentPatternIn)), subdivision(std::max(1, subdivision)), subdivisionVolume(subdivisionVolume), audioVolume(volume), sampleRate(sampleRate)
{
    if (mainFileBytes.empty())
    {
        throw std::invalid_argument("Main sound file cannot be empty");
    }

    mainSound = byteArrayToShortArray(mainFileBytes);
    accentedSound = accentedFileBytes.empty() ? mainSound : byteArrayToShortArray(accentedFileBytes);
    subdivisionSound = subdivisionFileBytes.empty() ? mainSound : byteArrayToShortArray(subdivisionFileBytes);

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
        writeCursor = playCursor = 0;
        if (metronomeThread.joinable())
        {
            metronomeThread.join();
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
}
void Metronome::SetBPM(int bpm)
{
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
void Metronome::SetAccentPattern(const std::vector<int> &patternIn)
{
    std::vector<int> normalized = NormalizeAccentPattern(patternIn);
    if (accentPattern != normalized)
    {
        bool wasPlaying = IsPlaying();
        if (wasPlaying)
        {
            Pause();
        }
        accentPattern = normalized;
        if (wasPlaying)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Play();
        }
    }
}
void Metronome::SetSubdivision(int newSubdivision)
{
    int normalized = std::max(1, newSubdivision);
    if (subdivision != normalized)
    {
        bool wasPlaying = IsPlaying();
        if (wasPlaying)
        {
            Pause();
        }
        subdivision = normalized;
        if (wasPlaying)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Play();
        }
    }
}
void Metronome::SetSubdivisionVolume(double newSubdivisionVolume)
{
    subdivisionVolume = newSubdivisionVolume;
    bool wasPlaying = IsPlaying();
    if (wasPlaying)
    {
        Pause();
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        Play();
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
    std::lock_guard<std::mutex>
        lock(paramMutex);
    int subBeatLength = static_cast<int>(sampleRate * 60.0 / (audioBpm * subdivision));
    int totalSlots = std::max(1, GetTotalBeats() * subdivision);
    std::vector<int16_t> bufferBar(subBeatLength * totalSlots, 0);

    // Pre-scale subdivision sound
    std::vector<int16_t> scaledSubdivision(subdivisionSound.size());
    for (size_t j = 0; j < subdivisionSound.size(); j++)
    {
        scaledSubdivision[j] = static_cast<int16_t>(subdivisionSound[j] * subdivisionVolume);
    }

    for (int tick = 0; tick < totalSlots; tick++)
    {
        bool isDownbeat = (tick % subdivision) == 0;
        int beatIndex = tick / subdivision;
        const std::vector<int16_t> &sound = isDownbeat
            ? (IsAccentBeat(beatIndex) ? accentedSound : mainSound)
            : scaledSubdivision;
        int copyLength = min(subBeatLength, static_cast<int>(sound.size()));
        std::copy_n(sound.begin(), copyLength, bufferBar.begin() + tick * subBeatLength);
    }

    beatLength = subBeatLength;

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
        int totalSlots = std::max(1, GetTotalBeats() * subdivision);
        if (totalSlots < 2)
        {
            currentTick = 0;
        }
        else
        {
            currentTick++;
            if (currentTick >= totalSlots)
                currentTick = 0;
        }
        eventTickSink->Success(flutter::EncodableValue(currentTick));
    }
    bufferCV.notify_one();
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
    const int subBeatMs = 60000 / (audioBpm * subdivision);
    auto sleepUntil = std::chrono::steady_clock::now() +
                      std::chrono::milliseconds(subBeatMs);
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