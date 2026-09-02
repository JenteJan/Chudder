import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/settings/arguments_model.dart';
import 'package:fladder/providers/crash_log_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:fladder/util/svg_utils.dart';

bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.sharedPreferences,
    required this.applicationInfo,
    required this.applicationDirectory,
    required this.argumentsModel,
    required this.crashProvider,
  });

  final SharedPreferences sharedPreferences;
  final ApplicationInfo applicationInfo;
  final Directory applicationDirectory;
  final ArgumentsModel argumentsModel;
  final CrashLogNotifier crashProvider;
}

Future<AppBootstrapResult> bootstrapApplication(List<String> args) async {
  final crashProvider = CrashLogNotifier();

  if (kIsWeb) {
    final configString = await rootBundle.loadString('config/config.json');
    FladderConfig.fromJson(jsonDecode(configString) as Map<String, dynamic>);
  }

  // None of these depend on each other, and each one is a round trip to the
  // platform side. Awaited one after another they added up to most of the
  // time between the process starting and the first frame; together, the
  // slowest of them is the whole cost.
  final results = await Future.wait<Object?>([
    SharedPreferences.getInstance(),
    PackageInfo.fromPlatform(),
    kIsWeb ? Future.value(Directory('')) : getApplicationDocumentsDirectory(),
    resolveLeanBackEnabled(),
    isDesktopPlatform ? _resolveWindowArguments() : Future.value(''),
    // The icons are read from the bundle, not drawn, so this does not need
    // to finish before the first frame either; it only needs to have been
    // started. It shares the wait with the rest so nothing paints without it.
    SvgUtils.preCacheSVGs(),
  ]);

  final sharedPreferences = results[0] as SharedPreferences;
  final packageInfo = results[1] as PackageInfo;
  final applicationDirectory = results[2] as Directory;
  final leanBackEnabled = results[3] as bool;
  final windowArguments = results[4] as String;

  final applicationInfo = ApplicationInfo(
    name: packageInfo.appName.capitalize(),
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
    platform: defaultTargetPlatform,
  );

  final argumentsModel = ArgumentsModel.fromArguments(
    args,
    windowArguments,
    leanBackEnabled,
  );

  return AppBootstrapResult(
    sharedPreferences: sharedPreferences,
    applicationInfo: applicationInfo,
    applicationDirectory: applicationDirectory,
    argumentsModel: argumentsModel,
    crashProvider: crashProvider,
  );
}

Future<bool> resolveLeanBackEnabled() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }

  try {
    return await NativeVideoActivity().isLeanBackEnabled();
  } catch (e) {
    print('Leanback detection failed (non-TV Android device): $e');
    return false;
  }
}

Future<String> _resolveWindowArguments() async {
  try {
    final windowController = await WindowController.fromCurrentEngine();
    return windowController.arguments;
  } catch (e) {
    print('Window arguments resolution failed: $e');
    return '';
  }
}
