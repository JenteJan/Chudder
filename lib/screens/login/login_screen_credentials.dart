import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/login_screen_model.dart';
import 'package:chudder/providers/auth_provider.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/login/lock_screen.dart';
import 'package:chudder/screens/login/login_user_grid.dart';
import 'package:chudder/screens/login/widgets/advanced_login_options_dialog.dart';
import 'package:chudder/screens/login/widgets/connect_link_dialog.dart';
import 'package:chudder/screens/login/widgets/discover_servers_widget.dart';
import 'package:chudder/screens/login/widgets/quick_connect_panel.dart';
import 'package:chudder/screens/shared/animated_fade_size.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/shared/media/external_urls.dart' as ext;
import 'package:chudder/screens/shared/outlined_text_field.dart';
import 'package:chudder/screens/shared/passcode_input.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/auth_service.dart';
import 'package:chudder/util/deep_link_helper.dart';
import 'package:chudder/util/fladder_config.dart';
import 'package:chudder/util/localization_helper.dart';

/// Adding an account, in two steps: first the server's address, then - once
/// that server has answered - signing in to it. Quick Connect is the first
/// way offered when the server has it on; a password is the way around it.
class LoginScreenCredentials extends ConsumerStatefulWidget {
  final AuthLinkData? authLinkData;
  const LoginScreenCredentials({
    this.authLinkData,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _LoginScreenCredentialsState();
}

class _LoginScreenCredentialsState extends ConsumerState<LoginScreenCredentials> {
  TextEditingController serverTextController = TextEditingController(text: '');
  TextEditingController usernameController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  final FocusNode passwordFocusNode = FocusNode();

  bool loggingIn = false;

  /// Password sign-in chosen over the code on this server.
  bool usePassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.authLinkData != null) {
        loginUsingAuthLink(widget.authLinkData!);
      }
    });
  }

  Future<void> loginUsingAuthLink(AuthLinkData link) async {
    final pendingLink = link;
    serverTextController.text = pendingLink.serverUrl;
    usernameController.text = pendingLink.userName;
    passwordController.text = pendingLink.password ?? "";
    setState(() => usePassword = true);
    await ref.read(authProvider.notifier).setServer(pendingLink.serverUrl);
    if (!mounted || ref.read(authProvider).serverLoginModel == null) return;
    try {
      if (passwordController.text.isNotEmpty) {
        await loginUsingCredentials();
      } else {
        passwordFocusNode.requestFocus();
      }
    } catch (e) {
      log("Error during auto-login with auth link: $e");
      if (mounted) FladderSnack.show(context.localized.error);
    } finally {
      if (mounted) setState(() => loggingIn = false);
    }
  }

  @override
  void dispose() {
    serverTextController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverCredentials = ref.watch(authProvider.select((value) => value.serverLoginModel));
    final connecting = ref.watch(authProvider.select((value) => value.connecting));

    ref.listen(
      authProvider.select((value) => value.serverLoginModel?.tempCredentials.url),
      (previous, next) {
        if (next?.isNotEmpty == true) serverTextController.text = next!;
        // A new server starts on its own preferred way in.
        if (previous != next && widget.authLinkData == null && usernameController.text.isEmpty) {
          setState(() => usePassword = false);
        }
      },
    );

    final connected = serverCredentials != null && !connecting;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AnimatedFadeSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: connected
              ? KeyedSubtree(
                  key: ValueKey('sign-in:${serverCredentials.tempCredentials.url}'),
                  child: _signInStep(context, serverCredentials),
                )
              : KeyedSubtree(
                  key: const ValueKey('server'),
                  child: _serverStep(context),
                ),
        ),
      ),
    );
  }

  Widget _serverStep(BuildContext context) {
    final theme = Theme.of(context);
    final provider = ref.read(authProvider.notifier);
    final hasBaseUrl = ref.watch(authProvider.select((value) => value.hasBaseUrl));
    final connecting = ref.watch(authProvider.select((value) => value.connecting));
    final error = ref.watch(authProvider.select((value) => value.errorMessage));
    final accounts = ref.watch(authProvider.select((value) => value.accounts));
    final otherCredentials = accounts.map((e) => e.credentials).toList();
    final touch = AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch;

    void connect() {
      if (connecting) return;
      provider.setServer(serverTextController.text);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        _StepHeader(
          title: context.localized.loginConnectTitle,
          description: hasBaseUrl ? null : context.localized.loginConnectDescription,
          onBack: accounts.isNotEmpty ? provider.goUserSelect : null,
        ),
        if (!hasBaseUrl)
          OutlinedTextField(
            controller: serverTextController,
            autoFocus: !touch,
            enabled: !connecting,
            onSubmitted: (_) => connect(),
            onChanged: (_) => setState(() {}),
            autoFillHints: const [AutofillHints.url],
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            label: context.localized.loginServerAddress,
            placeHolder: context.localized.loginServerAddressHint,
            showPlaceHolderUnfocused: true,
          ),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: connecting || (!hasBaseUrl && serverTextController.text.trim().isEmpty) ? null : connect,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: connecting
                  ? Row(
                      key: const ValueKey('connecting'),
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            strokeCap: StrokeCap.round,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Text(context.localized.loginConnecting),
                      ],
                    )
                  : Row(
                      key: const ValueKey('connect'),
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Text(context.localized.loginConnect),
                        const Icon(IconsaxPlusLinear.arrow_right_3, size: 18),
                      ],
                    ),
            ),
          ),
        ),
        AnimatedFadeSize(
          child: error != null && !connecting ? _ErrorNotice(message: error) : const SizedBox(width: double.infinity),
        ),
        if (!hasBaseUrl) ...[
          DiscoverServersWidget(
            serverCredentials: otherCredentials,
            onPressed: (info) {
              serverTextController.text = info.address;
              provider.setServer(info.address);
            },
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => showConnectLinkDialog(context, (link) => loginUsingAuthLink(link)),
              icon: const Icon(IconsaxPlusLinear.link_1, size: 18),
              label: Text(context.localized.connectWithAuthLink),
            ),
          ),
        ],
      ],
    );
  }

  Widget _signInStep(BuildContext context, ServerLoginModel server) {
    final theme = Theme.of(context);
    final provider = ref.read(authProvider.notifier);
    final hasBaseUrl = ref.watch(authProvider.select((value) => value.hasBaseUrl));
    final accounts = ref.watch(authProvider.select((value) => value.accounts));
    final showCode = server.hasQuickConnect && !usePassword;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        _StepHeader(
          title: context.localized.loginSignInTitle,
          // Back to the saved accounts; "Change server" on the card is the
          // step back to the address.
          onBack: accounts.isNotEmpty ? provider.goUserSelect : null,
        ),
        _ServerCard(
          server: server,
          onChange: hasBaseUrl ? null : provider.changeServer,
        ),
        AnimatedFadeSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: showCode
              ? KeyedSubtree(
                  key: const ValueKey('code'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      QuickConnectPanel(onApproved: loginUsingSecret),
                      _OrDivider(),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => usePassword = true),
                        icon: const Icon(IconsaxPlusLinear.password_check, size: 18),
                        label: Text(context.localized.loginUsePassword),
                      ),
                    ],
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey('password'),
                  child: _passwordForm(context, server),
                ),
        ),
        if (server.serverMessage?.isNotEmpty == true) ...[
          const Divider(),
          // HTML, as Jellyfin's own login page shows it: a <br> was printed
          // as text.
          Opacity(
            opacity: 0.8,
            child: HtmlWidget(
              '<div style="text-align: center">${server.serverMessage ?? ""}</div>',
              textStyle: theme.textTheme.bodyMedium,
              onTapUrl: (url) async {
                await ext.launchUrl(context, url);
                return true;
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _passwordForm(BuildContext context, ServerLoginModel server) {
    final theme = Theme.of(context);
    final users = server.accounts;
    final touch = AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (users.isNotEmpty) ...[
          Opacity(
            opacity: 0.8,
            child: Text(
              context.localized.loginPickAccount,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: LoginUserGrid(
              users: users,
              onPressed: (value) {
                usernameController.text = value.name;
                passwordController.text = "";
                passwordFocusNode.requestFocus();
                setState(() {});
              },
            ),
          ),
        ],
        AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              OutlinedTextField(
                controller: usernameController,
                autoFocus: !touch && users.isEmpty && usernameController.text.isEmpty,
                autoFillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: (value) => setState(() {}),
                label: context.localized.userName,
              ),
              OutlinedTextField(
                controller: passwordController,
                autoFillHints: const [AutofillHints.password],
                keyboardType: TextInputType.visiblePassword,
                focusNode: passwordFocusNode,
                autocorrect: false,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) => enterCredentialsTryLogin?.call(),
                onChanged: (value) => setState(() {}),
                label: context.localized.password,
              ),
            ],
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: loggingIn ? null : enterCredentialsTryLogin,
                  child: loggingIn
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            strokeCap: StrokeCap.round,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            Text(context.localized.login),
                            const Icon(IconsaxPlusLinear.login_1, size: 18),
                          ],
                        ),
                ),
              ),
            ),
            if (FladderConfig.seerrBaseUrl?.isNotEmpty != true)
              Tooltip(
                message: context.localized.advanced,
                child: IconButton.filledTonal(
                  onPressed: () async {
                    final tempSeerrUrl = ref.read(authProvider.select((value) => value.tempSeerrUrl));
                    final result = await showAdvancedLoginOptionsDialog(
                      context,
                      initialSeerrUrl: tempSeerrUrl,
                    );
                    if (result != null) {
                      ref.read(authProvider.notifier).setTempSeerrUrl(result);
                    }
                  },
                  icon: const Icon(IconsaxPlusLinear.setting_3),
                ),
              ),
          ],
        ),
        if (server.hasQuickConnect) ...[
          _OrDivider(),
          OutlinedButton.icon(
            onPressed: () => setState(() => usePassword = false),
            icon: const Icon(IconsaxPlusLinear.scan_barcode, size: 18),
            label: Text(context.localized.loginUseCode),
          ),
        ],
      ],
    );
  }

  Future<void> Function()? get enterCredentialsTryLogin => emptyFields() ? null : () => loginUsingCredentials();

  Future<void> loginUsingCredentials() async {
    setState(() {
      loggingIn = true;
    });

    final response = await ref.read(authProvider.notifier).authenticateByName(
          usernameController.text,
          passwordController.text,
        );

    if (response?.isSuccessful == false) {
      FladderSnack.show(
          "(${response?.base.statusCode}) ${response?.base.reasonPhrase ?? context.localized.somethingWentWrongPasswordCheck}",
          context: context);
      setState(() {
        loggingIn = false;
      });
      return;
    }

    if (response?.body == null) {
      setState(() {
        loggingIn = false;
      });
      return;
    }

    final tempSeerrUrl = ref.read(authProvider.select((value) => value.tempSeerrUrl));
    if (tempSeerrUrl != null && tempSeerrUrl.isNotEmpty) {
      await _tryAuthenticateSeerr(tempSeerrUrl);
    }

    if (context.mounted) {
      await loggedInGoToHome(context, ref);
    }
  }

  Future<void> _tryAuthenticateSeerr(String seerrUrl) async {
    try {
      final username = usernameController.text.trim();
      final password = passwordController.text;

      final effectiveSeerrUrl = FladderConfig.seerrBaseUrl ?? seerrUrl;
      ref.read(userProvider.notifier).setSeerrServerUrl(effectiveSeerrUrl);

      final tempCookie = ref.read(authProvider.select((value) => value.tempSeerrSessionCookie));
      final cookie = tempCookie ??
          await ref.read(seerrApiProvider).authenticateJellyfin(
                username: username,
                password: password,
              );

      ref.read(userProvider.notifier).setSeerrSessionCookie(cookie);
      ref.read(userProvider.notifier).setSeerrApiKey('');
      ref.read(authProvider.notifier).setTempSeerrSessionCookie(null);

      if (context.mounted) {
        FladderSnack.show(context.localized.seerrLoggedIn, context: context);
      }
    } catch (e) {
      if (context.mounted) {
        FladderSnack.show(
          "${context.localized.seerrAuthenticateLocal}: ${e.toString()}",
          context: context,
        );
      }
    }
  }

  Future<void> loginUsingSecret(String secret) async {
    final response = await FladderSnack.showResponse(
      ref.read(authProvider.notifier).authenticateUsingSecret(secret),
    );
    if (response.isSuccess && context.mounted) {
      await loggedInGoToHome(context, ref);
    }
  }

  bool emptyFields() => usernameController.text.isEmpty;
}

/// A step's title, with the way back beside it when there is one.
class _StepHeader extends StatelessWidget {
  final String title;
  final String? description;
  final VoidCallback? onBack;
  const _StepHeader({required this.title, this.description, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            SizedBox(
              width: 40,
              child: onBack != null
                  ? IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: onBack,
                      icon: const Icon(IconsaxPlusLinear.arrow_left_2),
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        if (description != null)
          Opacity(
            opacity: 0.8,
            child: Text(
              description!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// The server this sign-in goes to, marked as reached.
class _ServerCard extends StatelessWidget {
  final ServerLoginModel server;
  final VoidCallback? onChange;
  const _ServerCard({required this.server, this.onChange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credentials = server.tempCredentials;
    final name = credentials.serverName.isNotEmpty ? credentials.serverName : credentials.url;
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          spacing: 12,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(IconsaxPlusBold.driver, color: theme.colorScheme.onPrimaryContainer),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    spacing: 6,
                    children: [
                      Icon(IconsaxPlusBold.tick_circle, size: 14, color: theme.colorScheme.primary),
                      Text(
                        context.localized.loginConnected,
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                      if (credentials.serverName.isNotEmpty)
                        Flexible(
                          child: Opacity(
                            opacity: 0.7,
                            child: Text(
                              "· ${credentials.url}",
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onChange != null)
              MediaQuery.sizeOf(context).width < 600
                  ? IconButton(
                      tooltip: context.localized.loginChangeServer,
                      onPressed: onChange,
                      icon: const Icon(IconsaxPlusLinear.edit_2, size: 20),
                    )
                  : TextButton(
                      onPressed: onChange,
                      child: Text(context.localized.loginChangeServer),
                    ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String message;
  const _ErrorNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Icon(IconsaxPlusLinear.danger, color: theme.colorScheme.onErrorContainer),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        const Expanded(child: Divider()),
        Opacity(
          opacity: 0.6,
          child: Text(context.localized.loginOr, style: Theme.of(context).textTheme.labelMedium),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

Future<void> loggedInGoToHome(BuildContext context, WidgetRef ref) async {
  ref.read(lockScreenActiveProvider.notifier).update((state) => false);
  if (context.mounted) {
    await context.router.replaceAll([const DashboardRoute()]);
  }
}

Future<void> _handleLogin(BuildContext context, AccountModel user, WidgetRef ref) async {
  await ref.read(authProvider.notifier).switchUser();
  await ref.read(sharedUtilityProvider).updateAccountInfo(user.copyWith(
        lastUsed: DateTime.now(),
      ));
  ref.read(userProvider.notifier).updateUser(user.copyWith(lastUsed: DateTime.now()));

  loggedInGoToHome(context, ref);
}

void tapLoggedInAccount(BuildContext context, AccountModel user, WidgetRef ref) async {
  Future<void> loginFunction() => _handleLogin(context, user, ref);
  switch (user.authMethod) {
    case Authentication.autoLogin:
      loginFunction();
      break;
    case Authentication.biometrics:
      final authenticated = await AuthService.authenticateUser(context, user);
      if (authenticated) {
        loginFunction();
      }
      break;
    case Authentication.passcode:
      if (context.mounted) {
        showPassCodeDialog(context, (newPin) {
          if (newPin == user.localPin) {
            loginFunction();
          } else {
            FladderSnack.show(context.localized.incorrectPinTryAgain, context: context);
          }
        });
      }
      break;
    case Authentication.none:
      loginFunction();
      break;
  }
}
