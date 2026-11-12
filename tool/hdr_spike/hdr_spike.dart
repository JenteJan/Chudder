// A test bench for the native HDR video window, on Chudder's own Windows
// runner. Build with `flutter build windows -t tool/hdr_spike/hdr_spike.dart`.
//
// Config comes from the JSON file named by CHUDDER_SPIKE_CONFIG:
//   {"file": "...", "placement": "insideView" | "belowView",
//    "props": {"vo": "gpu-next", ...}, "status": "<status.json path>"}
// Every second the display's HDR state and mpv's output state are written to
// the status file. Keys: o toggles an opaque page over everything (leaving the
// player), q quits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

const _channel = MethodChannel('chudder/hdr_video_window');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final config =
      jsonDecode(File(Platform.environment['CHUDDER_SPIKE_CONFIG']!).readAsStringSync()) as Map<String, dynamic>;
  runApp(SpikeApp(config: config));
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key, required this.config});
  final Map<String, dynamic> config;

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.info));
  final List<String> mpvLog = [];
  Map<String, Object?> status = {};
  bool opaque = false;
  Timer? timer;
  int? hwnd;

  @override
  void initState() {
    super.initState();
    player.stream.log.listen((e) {
      final line = '[${e.prefix}] ${e.level}: ${e.text.trim()}';
      if (mpvLog.length > 400) mpvLog.removeAt(0);
      mpvLog.add(line);
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_start());
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyO) {
      setState(() => opaque = !opaque);
      unawaited(_channel.invokeMethod('setVisible', {'visible': !opaque}));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ) exit(0);
    return false;
  }

  Future<void> _start() async {
    hwnd = await _channel.invokeMethod<int>('create', {'placement': widget.config['placement'] ?? 'insideView', 'seeThrough': widget.config['seeThrough'] == true});
    if (widget.config['placement'] == 'dcompProbe') {
      if (widget.config['seeThrough'] == true) {
        await _channel.invokeMethod('create', {'placement': 'belowView', 'seeThrough': true});
        await _channel.invokeMethod('setVisible', {'visible': true});
      }
      timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      return;
    }
    final native = player.platform as NativePlayer;
    await native.setProperty('wid', '$hwnd');
    final props = (widget.config['props'] as Map? ?? {}).cast<String, Object?>();
    for (final entry in props.entries) {
      await native.setProperty(entry.key, '${entry.value}');
    }
    await _channel.invokeMethod('setVisible', {'visible': true});
    await player.open(Media(widget.config['file'] as String));
    await player.setPlaylistMode(PlaylistMode.single);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    final native = player.platform as NativePlayer;
    Future<String?> prop(String name) async {
      try {
        return await native.getProperty(name);
      } catch (_) {
        return null;
      }
    }

    final display = await _channel.invokeMapMethod<String, Object?>('displayInfo');
    final next = <String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'hwnd': hwnd,
      'opaque': opaque,
      'display': display,
      'current-vo': await prop('current-vo'),
      'position': player.state.position.inMilliseconds,
      'video-params/gamma': await prop('video-params/gamma'),
      'video-params/primaries': await prop('video-params/primaries'),
      'video-target-params/gamma': await prop('video-target-params/gamma'),
      'video-target-params/primaries': await prop('video-target-params/primaries'),
      'video-target-params/max-luma': await prop('video-target-params/max-luma'),
      'hwdec-current': await prop('hwdec-current'),
      'log': mpvLog.where((l) => !l.contains('[cplayer]') || l.contains('error')).toList().reversed.take(60).toList(),
    };
    final path = widget.config['status'] as String?;
    if (path != null) File(path).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(next));
    if (mounted) setState(() => status = next);
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(color: Colors.white, fontSize: 16);
    final display = status['display'] as Map?;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          // The player's controls: opaque bars at the top and bottom, a
          // translucent panel, and nothing at all in between.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: Colors.indigo,
              padding: const EdgeInsets.all(12),
              child: Text(
                'TOP BAR (opaque) | display: ${display ?? '-'} | vo: ${status['current-vo']} | '
                'source ${status['video-params/gamma']} -> target ${status['video-target-params/gamma']} '
                '${status['video-target-params/primaries']} peak ${status['video-target-params/max-luma']}',
                style: style,
              ),
            ),
          ),
          Positioned(
            left: 40,
            top: 120,
            child: Container(
              width: 360,
              height: 160,
              color: Colors.black.withValues(alpha: 0.5),
              alignment: Alignment.center,
              child: Text('translucent panel (50% black)', style: style),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.deepOrange,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                FilledButton(onPressed: () => player.playOrPause(), child: const Text('play / pause')),
                const SizedBox(width: 16),
                Text('BOTTOM BAR (opaque) | o = opaque page, q = quit', style: style),
              ]),
            ),
          ),
          if (opaque)
            Positioned.fill(
              child: Container(
                color: Colors.teal,
                alignment: Alignment.center,
                child: Text('OPAQUE PAGE: no video may show anywhere', style: style.copyWith(fontSize: 32)),
              ),
            ),
        ]),
      ),
    );
  }
}
