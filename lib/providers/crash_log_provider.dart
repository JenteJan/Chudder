import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/models/error_log_model.dart';

final crashLogProvider = StateNotifierProvider<CrashLogNotifier, List<ErrorLogModel>>((ref) => CrashLogNotifier());

class CrashLogNotifier extends StateNotifier<List<ErrorLogModel>> {
  CrashLogNotifier() : super([]) {
    init();
  }

  late final Logger logger;
  final maxLength = 50;
  String? logFilePath;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 500);

  /// Every record from the `Cast*` loggers, appended to a rotating text file.
  /// The in-app ring buffer only keeps WARNING+ — useless for diagnosing a
  /// cast that died while the phone sat in a pocket, where the story is told
  /// by INFO-level session events (suspended/resumed/ended, PlayNow, stops).
  String? castLogPath;
  final List<String> _castBuffer = [];
  Timer? _castFlushTimer;
  // Raised from 512K/256K: this file is the only record of a SyncPlay or
  // websocket failure on a release build, and it has to still hold that
  // failure hours later when someone thinks to look.
  static const _castLogMaxBytes = 4 * 1024 * 1024;
  static const _castLogKeepBytes = 3 * 1024 * 1024;

  void init() async {
    logger = Logger.root;
    logger.level = Level.ALL;
    logger.onRecord.listen(logPrint);

    FlutterError.onError = (FlutterErrorDetails details) => logFile(details);

    PlatformDispatcher.instance.onError = (error, stack) {
      logFile(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Unhandled',
      ));
      return false;
    };

    if (!kIsWeb) {
      await _initializeLogFile();
      await _loadLogsFromFile();
    }
  }

  Future<void> _initializeLogFile() async {
    final directory = await getApplicationCacheDirectory();
    logFilePath = '${directory.path}/crash_logs.json';
    castLogPath = '${directory.path}/cast_log.txt';
  }

  Future<void> _loadLogsFromFile() async {
    if (logFilePath == null) return;

    try {
      final file = File(logFilePath!);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> jsonData = jsonDecode(content);
      state = jsonData.map((json) => ErrorLogModel.fromJson(json)).toList();
    } catch (e) {
      print('Failed to load crash logs: $e');
    }
  }

  Future<void> _saveLogsToFile() async {
    if (logFilePath == null) return;

    try {
      final file = File(logFilePath!);
      final jsonData = state.map((log) => log.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      print('Failed to save crash logs: $e');
    }
  }

  Future<void> clearLogs() async {
    state = [];
    if (!kIsWeb) {
      _debounceTimer?.cancel();
      await _saveLogsToFile();
    }
  }

  /// Appends the buffered cast records and trims the file to its tail when it
  /// outgrows the cap, so it survives weeks of sessions without growing
  /// unbounded but always holds the most recent failures.
  Future<void> _flushCastLog() async {
    _castFlushTimer = null;
    final path = castLogPath;
    if (path == null || _castBuffer.isEmpty) return;
    final lines = '${_castBuffer.join('\n')}\n';
    _castBuffer.clear();
    try {
      final file = File(path);
      await file.writeAsString(lines, mode: FileMode.append, flush: true);
      if (await file.length() > _castLogMaxBytes) {
        final content = await file.readAsString();
        final tail = content.substring(content.length - _castLogKeepBytes);
        // Cut at a line boundary so the file doesn't start mid-record.
        final firstNewline = tail.indexOf('\n');
        await file.writeAsString(firstNewline == -1 ? tail : tail.substring(firstNewline + 1), flush: true);
      }
    } catch (e) {
      if (kDebugMode) print('Failed to write cast log: $e');
    }
  }

  /// Flushes pending records and returns the cast log file for sharing, or
  /// null if nothing has been logged yet.
  Future<File?> castLogFile() async {
    await _flushCastLog();
    final path = castLogPath;
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _saveLogsToFile();
    });
  }

  void logPrint(LogRecord rec) {
    if (kDebugMode) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    } else if (rec.loggerName == 'Connectivity') {
      // Low-volume and diagnosis-critical: reachability behavior can only be
      // debugged on a release phone via logcat, and these are the lines that
      // tell the story.
      // ignore: avoid_print
      print('Connectivity: ${rec.message}');
    }
    if (!kIsWeb &&
        rec.level >= Level.INFO &&
        (rec.loggerName.startsWith('Cast') ||
            rec.loggerName == 'SyncPlay' ||
            rec.loggerName == 'WebSocket' ||
            rec.loggerName == 'Connectivity' ||
            rec.loggerName == 'Navigation')) {
      _castBuffer.add('${rec.time.toIso8601String()} [${rec.level.name}] ${rec.loggerName}: ${rec.message}'
          '${rec.error != null ? ' | ${rec.error}' : ''}'
          '${rec.stackTrace != null ? '\n${rec.stackTrace}' : ''}');
      _castFlushTimer ??= Timer(_debounceDuration, _flushCastLog);
    }
    if (rec.level > Level.INFO) {
      state = [ErrorLogModel.fromLogRecord(rec), ...state];
      if (state.length >= maxLength) {
        state = state.sublist(0, maxLength);
      }
      if (!kIsWeb) {
        _scheduleSave();
      }
    }
  }

  /// Image fetches fail routinely and in bursts — a series with no chapter
  /// thumbnails emits one 404 per image, and a single browse can produce
  /// dozens. Persisting them fills the [maxLength] ring buffer and evicts the
  /// records worth keeping, so they are printed in debug but never stored.
  static bool _isImageLoadFailure(FlutterErrorDetails details) {
    if (details.library == 'image resource service') return true;
    final description = details.exception.toString();
    return description.contains('CachedNetworkImageProvider') ||
        description.contains('Failed to load network image') ||
        (description.contains('Invalid statusCode') && description.contains('/Images/'));
  }

  void logFile(FlutterErrorDetails details) {
    if (_isImageLoadFailure(details)) {
      if (kDebugMode) {
        print('Image load failed: ${details.exception}');
      }
      return;
    }
    logger.severe('Flutter error: ${details.exception}', details.exception, details.stack);
    if (details.stack != null && kDebugMode) {
      print('${details.stack}');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
