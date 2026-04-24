#include "metronome_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/encodable_value.h>
#include <flutter/plugin_registrar_windows.h>
#include <iostream>
#include <vector>
#include <variant>

namespace metronome
{
  static int EncodableToInt(const flutter::EncodableValue &v)
  {
    if (const int32_t *p = std::get_if<int32_t>(&v))
      return static_cast<int>(*p);
    if (const int64_t *p = std::get_if<int64_t>(&v))
      return static_cast<int>(*p);
    return -1;
  }

  static std::vector<int> ReadAccentPattern(flutter::EncodableMap &arguments)
  {
    auto it = arguments.find(flutter::EncodableValue("accentPattern"));
    if (it == arguments.end())
      return {4};
    auto *list = std::get_if<flutter::EncodableList>(&it->second);
    if (!list || list->empty())
      return {4};
    std::vector<int> out;
    out.reserve(list->size());
    for (const auto &e : *list)
    {
      int v = EncodableToInt(e);
      if (v < 1)
        return {4};
      out.push_back(v);
    }
    return out;
  }

  static flutter::EncodableList AccentPatternToEncodable(const std::vector<int> &pattern)
  {
    flutter::EncodableList list;
    for (int v : pattern)
      list.push_back(flutter::EncodableValue(v));
    return list;
  }
  void MetronomePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
  {
    auto methodChannel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "metronome",
            &flutter::StandardMethodCodec::GetInstance());

    auto eventChannel =
        std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), "metronome_tick",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<MetronomePlugin>();

    methodChannel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    eventChannel->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<>>(
            [plugin_pointer = plugin.get()](
                const flutter::EncodableValue *arguments,
                std::unique_ptr<flutter::EventSink<>> &&events)
                -> std::unique_ptr<flutter::StreamHandlerError<>>
            {
              plugin_pointer->eventSink = std::shared_ptr<flutter::EventSink<flutter::EncodableValue>>(events.release());
              return nullptr;
            },
            [plugin_pointer = plugin.get()](const flutter::EncodableValue *arguments)
                -> std::unique_ptr<flutter::StreamHandlerError<>>
            {
              plugin_pointer->eventSink.reset();
              return nullptr;
            }));

    registrar->AddPlugin(std::move(plugin));
  }

  MetronomePlugin::MetronomePlugin()
  {
  }

  MetronomePlugin::~MetronomePlugin() {}

  void MetronomePlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    const auto &method = method_call.method_name();
    if (method == "init")
    {
      auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
      std::vector<uint8_t> mainFileBytes = std::get<std::vector<uint8_t>>(arguments[flutter::EncodableValue("mainFileBytes")]);
      std::vector<uint8_t> accentedFileBytes = std::get<std::vector<uint8_t>>(arguments[flutter::EncodableValue("accentedFileBytes")]);
      std::vector<int> accentPattern = ReadAccentPattern(arguments);
      int bpm = std::get<int>(arguments[flutter::EncodableValue("bpm")]);
      double volume = std::get<double>(arguments[flutter::EncodableValue("volume")]);
      int sampleRate = std::get<int>(arguments[flutter::EncodableValue("sampleRate")]);
      bool enableTickCallback = std::get<bool>(arguments[flutter::EncodableValue("enableTickCallback")]);

      metronome = std::make_unique<Metronome>(mainFileBytes, accentedFileBytes, bpm, accentPattern, volume, sampleRate);
      if (enableTickCallback && eventSink)
      {
        metronome->EnableTickCallback(eventSink);
      }
      result->Success(true);
    }
    else if (method == "play")
    {
      metronome->Play();
      result->Success(true);
    }
    else if (method == "pause")
    {
      metronome->Pause();
      result->Success(true);
    }
    else if (method == "stop")
    {
      metronome->Stop();
      result->Success(true);
    }
    else if (method == "setBPM")
    {
      auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
      int bpm = std::get<int>(arguments[flutter::EncodableValue("bpm")]);
      metronome->SetBPM(bpm);
      std::cout << "bpm " << bpm << std::endl;
      result->Success(true);
    }
    else if (method == "getBPM")
    {
      result->Success(flutter::EncodableValue(metronome->audioBpm));
    }
    else if (method == "setAccentPattern")
    {
      auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
      std::vector<int> accentPattern = ReadAccentPattern(arguments);
      metronome->SetAccentPattern(accentPattern);
      result->Success(true);
    }
    else if (method == "getAccentPattern")
    {
      result->Success(flutter::EncodableValue(AccentPatternToEncodable(metronome->accentPattern)));
    }
    else if (method == "setVolume")
    {
      auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
      double volume = std::get<double>(arguments[flutter::EncodableValue("volume")]);
      metronome->SetVolume(volume);
      result->Success(true);
    }
    else if (method == "getVolume")
    {
      result->Success(flutter::EncodableValue(metronome->GetVolume()));
    }
    else if (method == "setAudioFile")
    {
      auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
      auto mainFileBytes = std::get<std::vector<uint8_t>>(arguments[flutter::EncodableValue("mainFileBytes")]);
      auto accentedFileBytes = std::get<std::vector<uint8_t>>(arguments[flutter::EncodableValue("accentedFileBytes")]);
      metronome->SetAudioFile(mainFileBytes, accentedFileBytes);
      result->Success(true);
    }
    else if (method == "isPlaying")
    {
      result->Success(flutter::EncodableValue(metronome->IsPlaying()));
    }
    else if (method == "destroy")
    {
      if (eventSink)
      {
        eventSink.reset();
      }
      metronome->Destroy();
      result->Success(true);
    }
    else
    {
      result->NotImplemented();
    }
  }
}
