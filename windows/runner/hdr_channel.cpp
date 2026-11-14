#include "hdr_channel.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <windows.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#pragma comment(lib, "dxgi.lib")

namespace {

using SetHdrFn = bool (*)(FlutterDesktopViewRef, bool);

SetHdrFn ResolveSetHdr() {
  HMODULE engine = ::GetModuleHandleW(L"flutter_windows.dll");
  return engine == nullptr ? nullptr
                           : reinterpret_cast<SetHdrFn>(::GetProcAddress(
                                 engine, "FlutterDesktopViewSetHdr"));
}

// Whether the display showing |window| is in HDR right now: Windows reports
// the HDR10 colour space for an output only while "Use HDR" is on. An HDR
// swap chain on any other display is clipped at SDR white, which loses every
// highlight mpv would otherwise have tone-mapped into SDR.
bool DisplayIsHdr(HWND window) {
  if (window == nullptr) {
    return false;
  }
  HMONITOR monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
  if (FAILED(::CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    return false;
  }
  Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
  for (UINT a = 0; factory->EnumAdapters1(a, &adapter) != DXGI_ERROR_NOT_FOUND;
       a++) {
    Microsoft::WRL::ComPtr<IDXGIOutput> output;
    for (UINT o = 0; adapter->EnumOutputs(o, &output) != DXGI_ERROR_NOT_FOUND;
         o++) {
      Microsoft::WRL::ComPtr<IDXGIOutput6> output6;
      DXGI_OUTPUT_DESC1 desc = {};
      if (SUCCEEDED(output.As(&output6)) &&
          SUCCEEDED(output6->GetDesc1(&desc)) && desc.Monitor == monitor) {
        return desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020;
      }
    }
  }
  return false;
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
    if (call.method_name() == "displayHdr") {
      result->Success(flutter::EncodableValue(QueryDisplayHdr()));
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

bool HdrChannel::QueryDisplayHdr() {
  HWND window = view_ == nullptr ? nullptr
                                 : FlutterDesktopViewGetHWND(
                                       static_cast<FlutterDesktopViewRef>(view_));
  const bool hdr = DisplayIsHdr(window);
  display_hdr_ = hdr;
  return hdr;
}

void HdrChannel::CheckDisplay(HWND window, bool monitor_changes_only) {
  HMONITOR monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (monitor_changes_only && monitor == monitor_) {
    return;
  }
  monitor_ = monitor;
  // Nothing to tell before Dart has asked: it only cares while HDR video is
  // open, and asks when that starts.
  if (!display_hdr_.has_value()) {
    return;
  }
  const bool hdr = DisplayIsHdr(window);
  if (hdr == *display_hdr_) {
    return;
  }
  display_hdr_ = hdr;
  channel_->InvokeMethod("displayHdrChanged",
                         std::make_unique<flutter::EncodableValue>(hdr));
}

void HdrChannel::OnWindowMessage(HWND window, UINT message) {
  switch (message) {
    case WM_ENTERSIZEMOVE:
      moving_ = true;
      break;
    case WM_EXITSIZEMOVE:
      // A drag across displays settles when it is let go, not on the way.
      moving_ = false;
      CheckDisplay(window, true);
      break;
    case WM_WINDOWPOSCHANGED:
      // Win+Shift+Arrow, full screen or a program moving the window.
      if (!moving_) {
        CheckDisplay(window, true);
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
    case WM_ACTIVATE:
      // "Use HDR" switched in Settings: Windows does not say so directly, but
      // the display changes mode and the window is activated again after.
      CheckDisplay(window, false);
      break;
  }
}
