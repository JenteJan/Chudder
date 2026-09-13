import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:chudder/background/update_notifications_worker.dart' as update_worker;
import 'package:chudder/models/account_model.dart';
import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/update_notifications_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/websocket/jellyfin_websocket_provider.dart';
import 'package:chudder/routes/auto_router.dart';
import 'package:chudder/providers/router_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/login/lock_screen.dart';
import 'package:chudder/services/notification_service.dart';
import 'package:chudder/util/deep_link_helper.dart';
import 'package:chudder/wrappers/players/native_player.dart';

typedef PlatformAppBuilder = Widget Function(
  BuildContext context,
  AutoRouter autoRouter,
);

abstract class BaseAppWrapper extends ConsumerStatefulWidget {
  const BaseAppWrapper({super.key, required this.builder});

  final PlatformAppBuilder builder;
}

abstract class BaseAppWrapperState<T extends BaseAppWrapper> extends ConsumerState<T> with WidgetsBindingObserver {
  late final AutoRouter autoRouter = AutoRouter(ref: ref);

  DateTime _lastPaused = DateTime.now();
  bool _hidden = false;

  StreamSubscription<String?>? _notificationSub;
  bool get enableNotifications => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(routerProvider.notifier).state = autoRouter;
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(sharedUtilityProvider).loadSettings();
      await platformInit();
      await _initializeNotifications();
    });
  }

  Future<void> platformInit() async {}

  Future<void> _initializeNotifications() async {
    if (!enableNotifications) return;

    if (ref.read(argumentsStateProvider).skipNotifications) return;

    await NotificationService.init();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Workmanager().initialize(update_worker.callbackDispatcher);
      } catch (e) {
        log('Failed to initialize Workmanager for background tasks: $e');
      }
    }

    _notificationSub = NotificationService.notificationTapStream.listen((payload) {
      if (payload == null || payload.isEmpty) return;
      final route = payloadToRoute(Uri.parse(payload));
      if (route != null) autoRouter.push(route);
    });

    NotificationService.getInitialNotificationPayload().then((payload) {
      if (payload == null || payload.isEmpty) return;
      final route = payloadToRoute(Uri.parse(payload));
      if (route != null) autoRouter.push(route);
    });

    try {
      await ref.read(updateNotificationsProvider).registerBackgroundTask();
    } catch (e) {
      log('Failed to register background task for update notifications: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ignoreLifeCycle = ref.read(lockScreenActiveProvider) ||
        ref.read(userProvider) == null ||
        ref.read(videoPlayerProvider).lastState?.playing == true ||
        nativeActivityStarted;

    if (ignoreLifeCycle) {
      _lastPaused = DateTime.now();
      _hidden = false;
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (_hidden) {
          _enableTimeOut();
          _hidden = false;
        }
        break;
      case AppLifecycleState.paused:
        _hidden = true;
        _lastPaused = DateTime.now();
        break;
      default:
        break;
    }
  }

  Future<void> _enableTimeOut() async {
    final timeOut = ref.read(clientSettingsProvider).timeOut;
    if (timeOut == null) return;

    final difference = DateTime.now().difference(_lastPaused);
    final lockMethod = ref.read(userProvider.select((value) => value?.authMethod));
    final shouldLock = Authentication.secureOptions.contains(lockMethod);

    if (difference > timeOut && shouldLock) {
      _lastPaused = DateTime.now();
      autoRouter.push(const LockRoute());
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Activate the app-level Jellyfin WebSocket for the whole session.
    // The provider connects/disconnects itself off userProvider; this
    // watch only ensures the keepAlive provider is instantiated.
    ref.watch(jellyfinWebSocketControllerProvider);
    // And the listener that folds the server's own account of what you have
    // watched into whatever is on screen. It subscribes when it is built and
    // to nothing else, so something has to build it.
    ref.watch(userDataUpdatesProvider);
    return widget.builder(
      context,
      autoRouter,
    );
  }
}
