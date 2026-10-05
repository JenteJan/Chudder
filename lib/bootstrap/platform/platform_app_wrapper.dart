import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/bootstrap/platform/base_app_wrapper.dart';
import 'package:chudder/bootstrap/platform/desktop_platform_wrapper.dart';
import 'package:chudder/bootstrap/platform/mobile_app_wrapper.dart';
import 'package:chudder/bootstrap/platform/web_app_wrapper.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';

class PlatformAppWrapper extends ConsumerStatefulWidget {
  const PlatformAppWrapper({super.key, required this.builder});

  final PlatformAppBuilder builder;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PlatformAppWrapperState();
}

class _PlatformAppWrapperState extends ConsumerState<PlatformAppWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Whether the app actually left the screen, as opposed to only losing
  /// focus to the notification shade or a permission dialog. Only a real
  /// return from the background warrants starting the connections over.
  bool _wasBackgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final connectivity = ref.read(connectivityStatusProvider.notifier);
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _wasBackgrounded = true;
        connectivity.onBackgrounded();
      case AppLifecycleState.resumed:
        if (_wasBackgrounded) {
          _wasBackgrounded = false;
          connectivity.onResumed();
        } else {
          // Safety check to ensure connectivity status is up to date when the app is resumed
          connectivity.checkConnectivity();
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return WebAppWrapper(builder: widget.builder);

    if (AdaptiveLayout.isDesktop(context)) return DesktopAppWrapper(builder: widget.builder);

    return MobileAppWrapper(builder: widget.builder);
  }
}
