import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// How much physical memory the machine has, and how much of it is free for
/// the taking - not what this app uses, but what is left for anyone.
class SystemMemory {
  const SystemMemory({required this.totalBytes, required this.availableBytes});

  final int totalBytes;
  final int availableBytes;

  double get availableShare => totalBytes <= 0 ? 1 : availableBytes / totalBytes;

  /// Whether [read] can tell on this platform. Windows asks the system; Linux
  /// and Android read /proc/meminfo. Elsewhere only the system's own warning
  /// (didHaveMemoryPressure) is there to go by.
  static bool get supported => (Platform.isWindows || Platform.isLinux || Platform.isAndroid);

  /// The machine's memory now, or null where it cannot be read.
  static SystemMemory? read() {
    if (!supported) return null;
    try {
      return Platform.isWindows ? _windows() : _procMeminfo();
    } catch (_) {
      return null;
    }
  }

  static SystemMemory? _procMeminfo() {
    int? field(List<String> lines, String name) {
      final line = lines.where((line) => line.startsWith('$name:')).firstOrNull;
      final kb = int.tryParse(line?.split(RegExp(r'\s+'))[1] ?? '');
      return kb == null ? null : kb * 1024;
    }

    final lines = File('/proc/meminfo').readAsLinesSync();
    final total = field(lines, 'MemTotal');
    final available = field(lines, 'MemAvailable');
    if (total == null || available == null) return null;
    return SystemMemory(totalBytes: total, availableBytes: available);
  }

  static SystemMemory? _windows() {
    final status = calloc<_MemoryStatusEx>();
    try {
      status.ref.length = sizeOf<_MemoryStatusEx>();
      if (_globalMemoryStatusEx(status) == 0) return null;
      return SystemMemory(totalBytes: status.ref.totalPhys, availableBytes: status.ref.availPhys);
    } finally {
      calloc.free(status);
    }
  }

  static final _globalMemoryStatusEx = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Int32 Function(Pointer<_MemoryStatusEx>), int Function(Pointer<_MemoryStatusEx>)>(
        'GlobalMemoryStatusEx',
      );
}

/// MEMORYSTATUSEX.
final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int memoryLoad;
  @Uint64()
  external int totalPhys;
  @Uint64()
  external int availPhys;
  @Uint64()
  external int totalPageFile;
  @Uint64()
  external int availPageFile;
  @Uint64()
  external int totalVirtual;
  @Uint64()
  external int availVirtual;
  @Uint64()
  external int availExtendedVirtual;
}
