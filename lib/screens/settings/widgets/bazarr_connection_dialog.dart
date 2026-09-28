import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/bazarr_credentials_model.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/util/localization_helper.dart';

Future<void> showBazarrConnectionDialog(BuildContext context) {
  return showDialogAdaptive(
    context: context,
    builder: (context) => const BazarrConnectionDialog(),
  );
}

/// Connects the account to a Bazarr: its address and API key, checked
/// against Bazarr before they are kept.
class BazarrConnectionDialog extends ConsumerStatefulWidget {
  const BazarrConnectionDialog({super.key});

  @override
  ConsumerState<BazarrConnectionDialog> createState() => _BazarrConnectionDialogState();
}

class _BazarrConnectionDialogState extends ConsumerState<BazarrConnectionDialog> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _checking = false;
  bool _showKey = false;
  String? _error;
  String? _connectedVersion;

  @override
  void initState() {
    super.initState();
    final credentials = ref.read(userProvider)?.bazarrCredentials;
    _url = TextEditingController(text: credentials?.serverUrl ?? '');
    _key = TextEditingController(text: credentials?.apiKey ?? '');
    if (credentials?.isConfigured ?? false) unawaited(_check(save: false));
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _check({bool save = true}) async {
    final credentials = BazarrCredentialsModel(serverUrl: _url.text.trim(), apiKey: _key.text.trim());
    if (!credentials.isConfigured) {
      setState(() => _error = context.localized.bazarrMissingFields);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final client = BazarrClient(credentials);
    final localized = context.localized;
    try {
      final version = await client.version();
      if (!mounted) return;
      if (save) ref.read(userProvider.notifier).setBazarrCredentials(credentials);
      setState(() => _connectedVersion = version);
      if (save) Navigator.of(context).pop();
    } on BazarrException catch (error) {
      if (!mounted) return;
      setState(() {
        _connectedVersion = null;
        _error = switch (error.error) {
          BazarrError.unauthorized => localized.bazarrWrongKey,
          BazarrError.notBazarr || BazarrError.notFound => localized.bazarrNotBazarr,
          _ => localized.bazarrUnreachable(error.message ?? error.error.name),
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectedVersion = null;
        _error = kIsWeb ? localized.bazarrUnreachableWeb : localized.bazarrUnreachable('$error');
      });
    } finally {
      client.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = ref.watch(userProvider.select((u) => u?.bazarrCredentials?.isConfigured ?? false));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Row(
              children: [
                Expanded(child: Text('Bazarr', style: theme.textTheme.titleLarge)),
                IconButton(
                  tooltip: context.localized.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(IconsaxPlusLinear.close_circle),
                ),
              ],
            ),
            Text(context.localized.bazarrExplainer, style: theme.textTheme.bodyMedium),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.localized.bazarrAddress,
                hintText: 'http://192.168.1.10:6767',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _connectedVersion = null),
            ),
            TextField(
              controller: _key,
              autocorrect: false,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: context.localized.bazarrApiKey,
                helperText: context.localized.bazarrApiKeyWhere,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(_showKey ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye),
                ),
              ),
              onChanged: (_) => setState(() => _connectedVersion = null),
              onSubmitted: (_) => _check(),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (_connectedVersion != null)
              Row(
                spacing: 8,
                children: [
                  Icon(IconsaxPlusLinear.tick_circle, color: theme.colorScheme.primary, size: 18),
                  Expanded(child: Text(context.localized.bazarrConnected(_connectedVersion!))),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 12,
              children: [
                if (connected)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: _checking
                        ? null
                        : () {
                            ref.read(userProvider.notifier).setBazarrCredentials(null);
                            Navigator.of(context).pop();
                          },
                    child: Text(context.localized.bazarrDisconnect),
                  ),
                FilledButton.icon(
                  onPressed: _checking ? null : () => _check(),
                  icon: _checking
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(IconsaxPlusLinear.link),
                  label: Text(context.localized.bazarrConnect),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The line under "Bazarr" in the settings.
String bazarrStatusLabel(BuildContext context, BazarrCredentialsModel? credentials) {
  if (credentials == null || !credentials.isConfigured) return context.localized.bazarrNotConnected;
  final uri = Uri.tryParse(credentials.serverUrl.contains('://') ? credentials.serverUrl : 'http://${credentials.serverUrl}');
  return context.localized.bazarrConnectedTo(uri?.host.isNotEmpty == true ? uri!.host : credentials.serverUrl);
}
