// Drives Chudder's own LibMPV with local files to test its automatic HDR
// switching: CHUDDER_PROBE_FILES is a ';'-separated list; key n opens the
// next one. Prints "probe: playing <file>" and LibMPV's HDR log lines.
// Build with `flutter build windows -t tool/hdr_spike/libmpv_probe.dart`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/wrappers/players/lib_mpv.dart';
import 'package:chudder/wrappers/players/windows_hdr.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const LibMpvProbe());
}

class LibMpvProbe extends StatefulWidget {
  const LibMpvProbe({super.key});

  @override
  State<LibMpvProbe> createState() => _LibMpvProbeState();
}

class _LibMpvProbeState extends State<LibMpvProbe> {
  final player = LibMPV();
  late final List<String> files = Platform.environment['CHUDDER_PROBE_FILES']!.split(';');
  int index = 0;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_start());
  }

  Future<void> _start() async {
    await player.init(VideoPlayerSettingsModel());
    await _open();
    setState(() => ready = true);
  }

  Future<void> _open() async {
    final file = files[index % files.length];
    await player.loadVideo(file, false, startPosition: const Duration(seconds: 5));
    stdout.writeln('probe: playing $file');
    if (mounted) setState(() {});
  }

  bool _onKey(KeyEvent event) {
    // b steps the HDR brightness the way the options sheet does.
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyB) {
      final steps = HdrBrightness.values;
      final next = steps[(steps.indexWhere((s) => s.paperWhiteNits == WindowsHdr.paperWhiteNits.value) + 1) % steps.length];
      WindowsHdr.paperWhiteNits.value = next.paperWhiteNits;
      stdout.writeln('probe: brightness ${next.name}');
      return true;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyN) {
      index++;
      unawaited(_open());
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 18);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (ready)
            Positioned.fill(
              child: player.videoWidget(const Key('probe'), BoxFit.contain) ?? const SizedBox.shrink(),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: const Color(0xFF3F51B5),
              padding: const EdgeInsets.all(12),
              child: Text('TOP BAR | ${files[index % files.length].split(r'\').last}', style: style),
            ),
          ),
        ]),
      ),
    );
  }
}
