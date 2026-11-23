import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/providers/discovery_consent_provider.dart';
import 'package:chudder/providers/discovery_provider.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/fladder_config.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/theme_extensions.dart';

class DiscoverServersWidget extends ConsumerStatefulWidget {
  final List<CredentialsModel> serverCredentials;
  final Function(DiscoveryInfo server) onPressed;
  const DiscoverServersWidget({
    required this.serverCredentials,
    required this.onPressed,
    super.key,
  });

  @override
  ConsumerState<DiscoverServersWidget> createState() => _DiscoverServersWidgetState();
}

class _DiscoverServersWidgetState extends ConsumerState<DiscoverServersWidget> {
  bool _requested = false;

  Future<void> _scan() async {
    final scannedBefore = _requested;
    setState(() => _requested = true);
    // The first press starts the provider; a later one scans again.
    if (scannedBefore) {
      ref.invalidate(serverDiscoveryProvider);
    }
    await ref.read(serverDiscoveryConsentProvider.notifier).choose();
  }

  @override
  Widget build(BuildContext context) {
    final serverCredentials = widget.serverCredentials;
    final onPressed = widget.onPressed;
    if (FladderConfig.baseUrl?.isNotEmpty == true) return const SizedBox.shrink();
    final existingServers = serverCredentials
        .map(
          (credentials) => DiscoveryInfo(
            id: credentials.serverId,
            name: credentials.serverName,
            address: credentials.url,
            endPointAddress: null,
          ),
        )
        .toSet()
        .toList();
    // Scanning is what makes iOS, macOS, Android and Windows ask for local network
    // access or firewall rights, so there it waits until the user asks, or has asked
    // before.
    final scanning = _requested || !serverDiscoveryNeedsPermission || ref.watch(serverDiscoveryConsentProvider);
    final discoverdServersStream = scanning ? ref.watch(serverDiscoveryProvider) : null;
    // A plain column: the list never scrolls, and a nested scrollable hides its
    // cards from a remote moving down from the address field.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (existingServers.isNotEmpty) ...[
          Row(
            children: [
              Text(
                context.localized.saved,
                style: context.textTheme.bodyLarge,
              ),
              const Spacer(),
              const Opacity(opacity: 0.65, child: Icon(IconsaxPlusLinear.bookmark, size: 16)),
            ],
          ),
          const SizedBox(height: 4),
          ...existingServers
              .map(
                (server) => _ServerInfoCard(
                  server: server,
                  onPressed: onPressed,
                ),
              )
              .toList()
              .addInBetween(const SizedBox(height: 8)),
        ],
        if (!kIsWeb) ...[
          const Divider(),
          Row(
            children: [
              Text(
                context.localized.discovered,
                style: context.textTheme.bodyLarge,
              ),
              const Spacer(),
              if (scanning && serverDiscoveryNeedsPermission)
                IconButton(
                  tooltip: context.localized.findServers,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: discoverdServersStream?.isLoading == true ? null : _scan,
                  icon: const Icon(IconsaxPlusBold.airdrop),
                )
              else
                const Opacity(opacity: 0.65, child: Icon(IconsaxPlusBold.airdrop, size: 16)),
            ],
          ),
          const SizedBox(height: 4),
          if (discoverdServersStream == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _scan,
                  icon: const Icon(IconsaxPlusBold.airdrop),
                  label: Text(context.localized.findServers),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: 0.65,
                  child: Text(
                    context.localized.findServersHint,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          else
            discoverdServersStream.when(
            data: (data) {
              final servers = data.where((discoverdServer) => !existingServers.contains(discoverdServer));
              return servers.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...servers.map(
                          (serverInfo) => _ServerInfoCard(
                            server: serverInfo,
                            onPressed: onPressed,
                          ),
                        )
                      ].toList().addInBetween(const SizedBox(height: 8)),
                    )
                  : Center(
                      child: Opacity(
                      opacity: 0.65,
                      child: Text(
                        context.localized.noServersFound,
                        style: context.textTheme.bodyLarge,
                      ),
                    ));
            },
            error: (error, stackTrace) => Text(context.localized.error),
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 24.0,
                child: CircularProgressIndicator(strokeCap: StrokeCap.round),
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  final Function(DiscoveryInfo server) onPressed;
  final DiscoveryInfo server;
  const _ServerInfoCard({
    required this.server,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Selected, a card keeps its colours and wears the ring, as the account
    // cards do. A button turned inside out left this text pale on pale.
    return FocusButton(
      onTap: () => onPressed(server),
      darkOverlay: false,
      borderRadius: FladderTheme.defaultShape.borderRadius,
      child: Card(
        margin: EdgeInsets.zero,
        shape: FladderTheme.defaultShape,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    IconsaxPlusBold.driver,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: context.textTheme.bodyLarge,
                    ),
                    Opacity(
                      opacity: 0.6,
                      child: Text(
                        server.address,
                        style: context.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Opacity(opacity: 0.7, child: Icon(IconsaxPlusLinear.arrow_right_3, size: 18))
            ].addInBetween(const SizedBox(width: 12)),
          ),
        ),
      ),
    );
  }
}
