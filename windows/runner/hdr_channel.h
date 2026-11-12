#ifndef RUNNER_HDR_CHANNEL_H_
#define RUNNER_HDR_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>

// "chudder/hdr": switches the window between an SDR and an HDR (scRGB)
// swap chain on an engine built with HDR support (FlutterDesktopViewSetHdr).
// On a stock engine the export is missing and "supported" answers false, so
// the runner builds and runs on either.
//
// Methods:
//   supported -> bool
//   displayHdr -> bool (whether the window's display is in HDR right now)
//   setHdr {enabled: bool} -> bool (whether the engine took the request)
class HdrChannel {
 public:
  explicit HdrChannel(flutter::FlutterEngine* engine);

 private:
  void* view_ = nullptr;  // FlutterDesktopViewRef
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_HDR_CHANNEL_H_
