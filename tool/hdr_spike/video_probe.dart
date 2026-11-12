// Video test bench for HDR output: plays CHUDDER_PROBE_FILE through media_kit
// (texture path, as Chudder does), pauses on a fixed frame, and draws opaque
// "controls" over it. CHUDDER_HDR_OUTPUT=1 switches the output to HDR.
// Build with `flutter build windows -t tool/hdr_spike/video_probe.dart`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:chudder/wrappers/players/windows_hdr.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const VideoProbe());
}

class VideoProbe extends StatefulWidget {
  const VideoProbe({super.key});

  @override
  State<VideoProbe> createState() => _VideoProbeState();
}

class _VideoProbeState extends State<VideoProbe> {
  final player = Player();
  late final controller = VideoController(player);
  String status = 'starting';

  bool hdr = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_start());
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyH) {
      unawaited(_setHdr(!hdr));
      return true;
    }
    return false;
  }

  /// Window first, then the output, as LibMPV does.
  Future<void> _setHdr(bool enabled) async {
    final platform = await controller.platform.future as dynamic;
    if (enabled) {
      final window = await WindowsHdr.setHdr(true);
      final output = await platform.setHdr(true) as bool;
      stdout.writeln('probe: HDR on: window $window output $output');
    } else {
      final output = await platform.setHdr(false) as bool;
      final window = await WindowsHdr.setHdr(false);
      stdout.writeln('probe: HDR off: window $window output $output');
    }
    hdr = enabled;
    if (mounted) setState(() => status = enabled ? 'HDR' : 'SDR');
  }

  Future<void> _start() async {
    final env = Platform.environment;
    final paperWhite = double.tryParse(env['CHUDDER_HDR_PAPER_WHITE'] ?? '');
    if (paperWhite != null) {
      final platform = await controller.platform.future as dynamic;
      await platform.setHdrPaperWhite(paperWhite);
      stdout.writeln('probe: paper white $paperWhite');
    }
    stdout.writeln('probe: WindowsHdr.supported ${await WindowsHdr.supported()}');
    if (env['CHUDDER_HDR_OUTPUT'] == '1') {
      await _setHdr(true);
    } else {
      status = 'SDR';
    }
    await player.open(Media(env['CHUDDER_PROBE_FILE']!), play: false);
    await player.stream.duration.firstWhere((d) => d > Duration.zero);
    await player.seek(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 1));
    stdout.writeln('probe: ready, ${player.state.width}x${player.state.height}');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 18);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: Video(controller: controller, controls: NoVideoControls, fill: Colors.black)),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: const Color(0xFF3F51B5),
              padding: const EdgeInsets.all(12),
              child: Text('TOP BAR (opaque) | $status', style: style),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 90,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(12),
              child: const Text('controls scrim over the picture', style: style),
            ),
          ),
        ]),
      ),
    );
  }
}
