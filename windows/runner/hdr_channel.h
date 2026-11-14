#ifndef RUNNER_HDR_CHANNEL_H_
#define RUNNER_HDR_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <windows.h>

#include <memory>
#include <optional>

// "chudder/hdr": switches the window between an SDR and an HDR (scRGB)
// swap chain on an engine built with HDR support (FlutterDesktopViewSetHdr).
// On a stock engine the export is missing and "supported" answers false, so
// the runner builds and runs on either.
//
// Methods:
//   supported -> bool
//   displayHdr -> bool (whether the window's display is in HDR right now)
//   setHdr {enabled: bool} -> bool (whether the engine took the request)
//
// And to Dart:
//   displayHdrChanged (bool): the window moved to a display in or out of HDR,
//   or its display switched HDR on or off.
class HdrChannel {
 public:
  explicit HdrChannel(flutter::FlutterEngine* engine);

  // Every message of the top-level window, to notice a move to another
  // display and a display switching HDR on or off.
  void OnWindowMessage(HWND window, UINT message);

 private:
  bool QueryDisplayHdr();
  void CheckDisplay(HWND window, bool monitor_changes_only);

  void* view_ = nullptr;  // FlutterDesktopViewRef
  HMONITOR monitor_ = nullptr;
  bool moving_ = false;  // in a drag or resize, settled when it ends
  std::optional<bool> display_hdr_;  // last told to Dart, or asked by it
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_HDR_CHANNEL_H_
