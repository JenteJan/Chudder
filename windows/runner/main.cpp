#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <optional>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // The load-time benchmark (tool/perf) passes --perf-window=<x>,<y>: a
  // window placed there in physical pixels, off the taskbar and never
  // activated, so a run neither takes the focus nor covers anything.
  std::optional<Win32Window::Point> bench_origin;
  for (const std::string& argument : command_line_arguments) {
    int x = 0, y = 0;
    if (sscanf_s(argument.c_str(), "--perf-window=%d,%d", &x, &y) == 2) {
      bench_origin = Win32Window::Point(static_cast<unsigned int>(x),
                                        static_cast<unsigned int>(y));
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetUnobtrusive(bench_origin.has_value());
  Win32Window::Point origin = bench_origin.value_or(Win32Window::Point(10, 10));
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Chudder", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
