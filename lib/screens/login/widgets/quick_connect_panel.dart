import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/screens/shared/media/external_urls.dart' as ext;
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/clipboard_helper.dart';
import 'package:chudder/util/localization_helper.dart';

/// Sign-in by Quick Connect, on the page: asks the server for a code as soon
/// as it is shown, puts the code up large, and keeps asking whether someone
/// has approved it. [onApproved] gets the secret to sign in with.
class QuickConnectPanel extends ConsumerStatefulWidget {
  final Future<void> Function(String secret) onApproved;
  const QuickConnectPanel({required this.onApproved, super.key});

  @override
  ConsumerState<QuickConnectPanel> createState() => _QuickConnectPanelState();
}

enum _CodeState { requesting, waiting, expired, failed, approved }

class _QuickConnectPanelState extends ConsumerState<QuickConnectPanel> {
  QuickConnectResult? info;
  _CodeState codeState = _CodeState.requesting;
  RestartableTimer? timer;

  @override
  void initState() {
    super.initState();
    requestCode();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> requestCode() async {
    timer?.cancel();
    setState(() => codeState = _CodeState.requesting);
    try {
      final response = await ref.read(jellyApiProvider).quickConnectInitiate();
      if (!mounted) return;
      final body = response.body;
      if (response.isSuccessful && body?.code != null && body?.secret != null) {
        setState(() {
          info = body;
          codeState = _CodeState.waiting;
        });
        timer = RestartableTimer(const Duration(seconds: 1), poll);
      } else {
        setState(() => codeState = _CodeState.failed);
      }
    } catch (_) {
      if (mounted) setState(() => codeState = _CodeState.failed);
    }
  }

  Future<void> poll() async {
    final secret = info?.secret;
    if (secret == null || !mounted || codeState != _CodeState.waiting) return;
    try {
      final result = await ref.read(jellyApiProvider).quickConnectConnectGet(secret: secret);
      if (!mounted || secret != info?.secret || codeState != _CodeState.waiting) return;
      final newSecret = result.body?.secret;
      if (result.isSuccessful && result.body?.authenticated == true && newSecret != null) {
        setState(() => codeState = _CodeState.approved);
        await widget.onApproved(newSecret);
        // Sign-in failed after all: start over with a fresh code.
        if (mounted && codeState == _CodeState.approved) requestCode();
        return;
      }
      if (!result.isSuccessful) {
        // The server forgets a code once it runs out.
        setState(() => codeState = _CodeState.expired);
        return;
      }
    } catch (_) {
      // A dropped request is not an expired code; ask again.
    }
    timer?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = info?.code;
    final touch = AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch;
    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final showCode = code != null && (codeState == _CodeState.waiting || codeState == _CodeState.approved);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(
          context.localized.loginSignInWithCode,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        Opacity(
          opacity: 0.8,
          child: Text(
            context.localized.loginCodeInstructions,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 96,
          child: switch (codeState) {
            _CodeState.requesting => const Center(child: CircularProgressIndicator(strokeCap: StrokeCap.round)),
            _ when showCode => _CodeBox(code: code, autofocus: !touch),
            _CodeState.expired => _CodeNotice(
                icon: IconsaxPlusLinear.timer_1,
                text: context.localized.loginCodeExpired,
              ),
            _ => _CodeNotice(
                icon: IconsaxPlusLinear.danger,
                text: context.localized.quickConnectPostFailed,
              ),
          },
        ),
        SizedBox(
          height: 20,
          child: switch (codeState) {
            _CodeState.waiting || _CodeState.approved => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 10,
                children: [
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, strokeCap: StrokeCap.round),
                  ),
                  Flexible(
                    child: Opacity(
                      opacity: 0.75,
                      child: Text(
                        codeState == _CodeState.approved
                            ? context.localized.loginSigningIn
                            : context.localized.loginCodeWaiting,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            _ => const SizedBox.shrink(),
          },
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!dPad && codeState == _CodeState.waiting)
              TextButton.icon(
                onPressed: openWebQuickConnect,
                icon: const Icon(IconsaxPlusLinear.export_1, size: 18),
                label: Text(context.localized.openJellyfinQuickConnect),
              ),
            if (codeState == _CodeState.expired || codeState == _CodeState.failed)
              FilledButton.tonalIcon(
                autofocus: !touch,
                onPressed: requestCode,
                icon: const Icon(IconsaxPlusLinear.refresh, size: 18),
                label: Text(context.localized.loginNewCode),
              )
            else
              TextButton.icon(
                onPressed: codeState == _CodeState.waiting ? requestCode : null,
                icon: const Icon(IconsaxPlusLinear.refresh, size: 18),
                label: Text(context.localized.loginNewCode),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> openWebQuickConnect() async {
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return;
    final url = buildServerUriFromBase(
      baseUrl,
      pathSegments: ['web'],
      relativeUrl: '#/quickconnect',
    )?.toString();
    if (url != null && url.isNotEmpty) {
      await ext.launchUrl(context, url);
    }
  }
}

class _CodeBox extends StatelessWidget {
  final String code;
  final bool autofocus;
  const _CodeBox({required this.code, required this.autofocus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: autofocus,
          onTap: () => context.copyToClipboard(code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: Text(
              code,
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              semanticsLabel: code.split('').join(' '),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CodeNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Icon(icon, color: theme.colorScheme.error),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}
