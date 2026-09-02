import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/navigation_history_provider.dart';
import 'package:fladder/widgets/shared/back_intent_dpad.dart';
import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/bootstrap/platform/platform_app_wrapper.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/localization_delegates.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/crash_log_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/themes_data.dart';
import 'package:fladder/util/window_drag_strip.dart';
import 'package:fladder/widgets/media_query_scaler.dart';
import 'package:fladder/widgets/pip_lifecycle_controller.dart';
import 'package:fladder/widgets/shared/adaptive_color.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrap = await bootstrapApplication(args);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => bootstrap.sharedPreferences),
        applicationInfoProvider.overrideWith((ref) => bootstrap.applicationInfo),
        crashLogProvider.overrideWith((ref) => bootstrap.crashProvider),
        argumentsStateProvider.overrideWith((ref) => bootstrap.argumentsModel),
        syncProvider.overrideWith((ref) => SyncNotifier(ref, bootstrap.applicationDirectory)),
      ],
      child: AdaptiveLayoutBuilder(
        child: (context) => const Main(),
      ),
    ),
  );
}

class Main extends ConsumerWidget {
  const Main({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformAppWrapper(
      builder: (context, autoRouter) {
        return _FladderApp(
          autoRouter: autoRouter,
        );
      },
    );
  }
}

class _FladderApp extends ConsumerWidget {
  const _FladderApp({
    required this.autoRouter,
  });

  final AutoRouter autoRouter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(clientSettingsProvider.select((value) => value.themeMode));
    final amoledBlack = ref.watch(clientSettingsProvider.select((value) => value.amoledBlack));
    final mouseDrag = ref.watch(clientSettingsProvider.select((value) => value.mouseDragSupport));
    final language = ref.watch(clientSettingsProvider
        .select((value) => value.selectedLocale ?? WidgetsBinding.instance.platformDispatcher.locale));
    final scrollBehaviour = const MaterialScrollBehavior();
    final amoledOverwrite = amoledBlack ? Colors.black : null;

    return AdaptiveColor(
      child: (darkTheme, lightTheme) => ThemesData(
        light: lightTheme,
        dark: darkTheme,
        child: MaterialApp.router(
          theme: lightTheme,
          scrollBehavior: scrollBehaviour.copyWith(
            dragDevices: {
              ...scrollBehaviour.dragDevices,
              mouseDrag ? PointerDeviceKind.mouse : null,
            }.nonNulls.toSet(),
          ),
          localizationsDelegates: FladderLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: language,
          localeResolutionCallback: (locale, supportedLocales) {
            const fallback = Locale('en');
            if (locale == null) return fallback;
            if (supportedLocales.contains(locale)) {
              return locale;
            }
            final matchByLanguage = supportedLocales.firstWhere(
              (l) => l.languageCode == locale.languageCode,
              orElse: () => fallback,
            );

            return matchByLanguage;
          },
          builder: (context, child) => MediaQueryScaler(
            child: LocalizationContextWrapper(
              child: PipLifecycleController(
                // Above the navigator so the title-bar strip stays draggable
                // while modals (cast picker, dialogs) are open.
                child: WindowDragStrip(
                  // App-wide back: the mouse's back button and backspace used
                  // to be handled inside the navigation body, which wrapped
                  // every page while details and settings were children of the
                  // same router. They are the root's own pages now, so the
                  // handler has to sit above the router instead - and takes the
                  // root router explicitly, having no router scope of its own.
                  child: BackIntentDpad(
                    // The pop itself is recorded by NavigationHistoryObserver,
                    // so every way of going back feeds the forward history,
                    // not just this button.
                    onBack: autoRouter.maybePop,
                    onForward: () => ref.read(navigationHistoryProvider).goForward(autoRouter),
                    child: child ?? Container(),
                  ),
                ),
              ),
              currentLocale: language,
            ),
            enable: ref.read(argumentsStateProvider).leanBackMode,
          ),
          debugShowCheckedModeBanner: false,
          darkTheme: amoledOverwrite == null
              ? darkTheme
              : darkTheme.copyWith(
                  scaffoldBackgroundColor: amoledOverwrite,
                  cardColor: amoledOverwrite,
                  canvasColor: amoledOverwrite,
                  colorScheme: darkTheme.colorScheme.copyWith(
                    surface: amoledOverwrite,
                    surfaceContainerHighest: amoledOverwrite,
                    surfaceContainerLow: amoledOverwrite,
                  ),
                ),
          themeMode: themeMode,
          routerConfig: autoRouter.config(
            deepLinkBuilder: (deepLink) => deepLinkBuilder(deepLink.uri),
            navigatorObservers: () => [
              NavigationHistoryObserver(ref.read(navigationHistoryProvider)),
            ],
          ),
        ),
      ),
    );
  }
}
