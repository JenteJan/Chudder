import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/syncplay/syncplay_extensions.dart';

/// A small, unobtrusive corner pill explaining why playback is behaving
/// oddly while SyncPlay processes a command, corrects drift, or switches
/// items.
///
/// Deliberately NOT a centered overlay: drift corrections and quick commands
/// fire often during normal group playback, and a mid-screen card on every
/// one made the video unwatchable. The pill also only appears when the
/// syncing state has persisted for a moment — sub-second blips (a routine
/// pause/unpause, a single rate nudge) resolve before it ever shows.
class SyncPlayCommandIndicator extends ConsumerStatefulWidget {
  const SyncPlayCommandIndicator({super.key});

  @override
  ConsumerState<SyncPlayCommandIndicator> createState() => _SyncPlayCommandIndicatorState();
}

class _SyncPlayCommandIndicatorState extends ConsumerState<SyncPlayCommandIndicator> {
  /// How long the syncing state must persist before the pill appears.
  static const _showDelay = Duration(milliseconds: 600);

  Timer? _showTimer;
  bool _shown = false;

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  /// Called from build, so state flips are deferred (a timer for showing, a
  /// post-frame callback for hiding) — setState during build is illegal.
  void _syncVisibility(bool wanted) {
    if (wanted) {
      if (_shown || _showTimer != null) return;
      _showTimer = Timer(_showDelay, () {
        _showTimer = null;
        if (mounted) setState(() => _shown = true);
      });
    } else {
      _showTimer?.cancel();
      _showTimer = null;
      if (_shown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _shown && _showTimer == null) setState(() => _shown = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(isSyncPlayActiveProvider);
    final isProcessing = ref.watch(syncPlayProvider.select((s) => s.isProcessingCommand));
    final commandType = ref.watch(syncPlayProvider.select((s) => s.processingCommandType));
    final strategy = ref.watch(syncCorrectionStrategyProvider);
    final isSwitching = ref.watch(syncPlayStartPlaybackInProgressProvider);

    final hasCorrection = strategy != SyncCorrectionStrategy.none;
    final showCommand = isProcessing && commandType != null;
    _syncVisibility(isActive && (showCommand || hasCorrection || isSwitching));

    final scheme = Theme.of(context).colorScheme;
    final label = isSwitching
        ? context.localized.syncPlaySwitchingItem
        : showCommand
            ? commandType.syncPlayCommandOverlayLabel(context)
            : strategy != SyncCorrectionStrategy.none
                ? strategy.label(context)
                : context.localized.syncPlaySyncingWithGroup;

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            // Below the player's top control row so the pill never covers a
            // button.
            padding: const EdgeInsets.only(top: 72, right: 16),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _shown ? 0.85 : 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
