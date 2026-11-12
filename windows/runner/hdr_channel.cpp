#include "hdr_channel.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <windows.h>

namespace {

using SetHdrFn = bool (*)(FlutterDesktopViewRef, bool);

SetHdrFn ResolveSetHdr() {
  HMODULE engine = ::GetModuleHandleW(L"flutter_windows.dll");
  return engine == nullptr ? nullptr
                           : reinterpret_cast<SetHdrFn>(::GetProcAddress(
                                 engine, "FlutterDesktopViewSetHdr"));
}

}  // namespace

HdrChannel::HdrChannel(flutter::FlutterEngine* engine) {
  FlutterDesktopPluginRegistrarRef registrar =
      engine->GetRegistrarForPlugin("ChudderHdrChannel");
  view_ = FlutterDesktopPluginRegistrarGetView(registrar);
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "chudder/hdr",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    static const SetHdrFn set_hdr = ResolveSetHdr();
    if (call.method_name() == "supported") {
      result->Success(flutter::EncodableValue(set_hdr != nullptr));
      return;
    }
    if (call.method_name() == "setHdr") {
      bool enabled = false;
      if (const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto it = args->find(flutter::EncodableValue("enabled"));
        if (it != args->end()) {
          if (const auto* value = std::get_if<bool>(&it->second)) {
            enabled = *value;
          }
        }
      }
      const bool taken =
          set_hdr != nullptr && view_ != nullptr &&
          set_hdr(static_cast<FlutterDesktopViewRef>(view_), enabled);
      result->Success(flutter::EncodableValue(taken));
      return;
    }
    result->NotImplemented();
  });
}
