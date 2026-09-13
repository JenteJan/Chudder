import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/account_model.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/login/widgets/login_icon.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/shared/passcode_input.dart';
import 'package:chudder/screens/shared/route_wrapper.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/auth_service.dart';
import 'package:chudder/util/localization_helper.dart';

final lockScreenActiveProvider = StateProvider<bool>((ref) => false);

@RoutePage()
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> with WidgetsBindingObserver {
  bool poppingLockScreen = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        hackyFixForBlackNavbar();
      default:
        break;
    }
  }

  void hackyFixForBlackNavbar() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: []);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lockScreenActiveProvider.notifier).update((state) => true);
      final user = ref.read(userProvider);
      if (user != null && user.authMethod != Authentication.none && user.askForAuthOnLaunch) {
        tapLoggedInAccount(user);
      }
    });
    hackyFixForBlackNavbar();
  }

  void handleLogin(AccountModel user) {
    ref.read(lockScreenActiveProvider.notifier).update((state) => false);
    poppingLockScreen = true;
    context.router.pop();
  }

  void tapLoggedInAccount(AccountModel user) async {
    switch (user.authMethod) {
      case Authentication.autoLogin:
        handleLogin(user);
        break;
      case Authentication.biometrics:
        final authenticated = await AuthService.authenticateUser(context, user);
        if (authenticated && context.mounted) {
          handleLogin(user);
        }
        break;
      case Authentication.passcode:
        if (context.mounted) {
          showPassCodeDialog(context, (newPin) {
            if (newPin == user.localPin) {
              handleLogin(user);
            } else {
              FladderSnack.show(context.localized.incorrectPinTryAgain, context: context);
            }
          });
        }
        break;
      case Authentication.none:
        handleLogin(user);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    return RouteWrapper(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!poppingLockScreen) {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          floatingActionButton: FloatingActionButton(
            tooltip: context.localized.login,
            onPressed: () {
              ref.read(lockScreenActiveProvider.notifier).update((state) => false);
              context.router.replaceAll([LoginRoute()]);
            },
            child: const Icon(IconsaxPlusLinear.arrow_swap_horizontal),
          ),
          body: Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              direction: Axis.vertical,
              children: [
                const Icon(
                  IconsaxPlusLinear.lock_1,
                  size: 38,
                ),
                if (user != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 400,
                      maxWidth: 400,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(64.0),
                      child: LoginIcon(
                        user: user,
                        autoFocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
                        onPressed: () => tapLoggedInAccount(user),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
