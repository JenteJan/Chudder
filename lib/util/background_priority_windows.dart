import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

final _log = Logger('BackgroundPriority');

const int _normalPriorityClass = 0x00000020;
const int _belowNormalPriorityClass = 0x00004000;

// PROCESS_INFORMATION_CLASS ProcessPowerThrottling, and its execution-speed
// bit: set in both masks is EcoQoS on; in neither, Windows decides.
const int _processPowerThrottling = 4;
const int _throttleExecutionSpeed = 0x1;

final class _PowerThrottlingState extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int controlMask;
  @Uint32()
  external int stateMask;
}

typedef _GetCurrentProcessC = IntPtr Function();
typedef _GetCurrentProcess = int Function();
typedef _SetPriorityClassC = Int32 Function(IntPtr process, Uint32 priorityClass);
typedef _SetPriorityClass = int Function(int process, int priorityClass);
typedef _SetProcessInformationC = Int32 Function(IntPtr process, Int32 infoClass, Pointer<Void> info, Uint32 size);
typedef _SetProcessInformation = int Function(int process, int infoClass, Pointer<Void> info, int size);

class _Kernel32 {
  _Kernel32() : _lib = DynamicLibrary.open('kernel32.dll');
  final DynamicLibrary _lib;

  late final getCurrentProcess = _lib.lookupFunction<_GetCurrentProcessC, _GetCurrentProcess>('GetCurrentProcess');
  late final setPriorityClass = _lib.lookupFunction<_SetPriorityClassC, _SetPriorityClass>('SetPriorityClass');
  // Windows 8 and later; EcoQoS itself needs Windows 11, older ones ignore it.
  late final setProcessInformation =
      _lib.lookupFunction<_SetProcessInformationC, _SetProcessInformation>('SetProcessInformation');
}

_Kernel32? _kernel32;

/// [standing] is a ProcessStanding index: 0 normal, 1 yielding, 2 resting.
void applyProcessStanding(int standing) {
  if (!Platform.isWindows) return;
  try {
    final kernel = _kernel32 ??= _Kernel32();
    final process = kernel.getCurrentProcess();
    kernel.setPriorityClass(process, standing == 0 ? _normalPriorityClass : _belowNormalPriorityClass);

    final state = calloc<_PowerThrottlingState>();
    try {
      state.ref
        ..version = 1
        ..controlMask = standing == 2 ? _throttleExecutionSpeed : 0
        ..stateMask = standing == 2 ? _throttleExecutionSpeed : 0;
      kernel.setProcessInformation(process, _processPowerThrottling, state.cast(), sizeOf<_PowerThrottlingState>());
    } finally {
      calloc.free(state);
    }
  } catch (error) {
    _log.info('Could not change the process standing: $error');
  }
}
