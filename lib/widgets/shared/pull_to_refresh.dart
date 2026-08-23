import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/util/refresh_state.dart';

class PullToRefresh extends ConsumerStatefulWidget {
  final GlobalKey<RefreshIndicatorState>? refreshKey;
  final double? displacement;
  final bool refreshOnStart;
  final bool autoFocus;
  final bool contextRefresh;
  final Future<void> Function()? onRefresh;
  final Widget Function(BuildContext context) child;
  const PullToRefresh({
    required this.child,
    this.displacement,
    this.autoFocus = true,
    this.refreshOnStart = true,
    this.contextRefresh = true,
    required this.onRefresh,
    this.refreshKey,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends ConsumerState<PullToRefresh> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final FocusNode focusNode = FocusNode();

  GlobalKey<RefreshIndicatorState> get refreshKey {
    return (widget.refreshKey ?? _refreshIndicatorKey);
  }

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnStart) {
      Future.microtask(
        () => refreshKey.currentState?.show(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The screen went quiet while offline (loaders skip the network), so
    // when the server comes back nothing on it reloads by itself - the
    // banner cleared but the content stayed stale until a manual pull.
    ref.listen<bool>(offlineStateProvider, (previous, next) {
      if (previous == true && next == false) {
        refreshKey.currentState?.show();
      }
    });
    return RefreshState(
      refreshKey: refreshKey,
      refreshAble: widget.contextRefresh,
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        skipTraversal: true,
        descendantsAreFocusable: true,
        descendantsAreTraversable: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.f5) {
              refreshKey.currentState?.show();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          return KeyEventResult.ignored;
        },
        child: widget.onRefresh != null
            ? RefreshIndicator(
                displacement: widget.displacement ?? 80 + MediaQuery.of(context).viewPadding.top,
                key: refreshKey,
                // A manual refresh is an explicit "try again". While the app
                // believes it is offline it stops talking to the server, so
                // without this the pull did nothing and the user had to wait
                // for the 10s recheck timer to notice the connection is back.
                onRefresh: () async {
                  if (ref.read(offlineStateProvider)) {
                    final connectivity = ref.read(connectivityStatusProvider.notifier);
                    await connectivity.checkConnectivity();
                    // Right after reconnecting, the first probe can lose the
                    // race against the radio coming back up. One retry inside
                    // the same gesture beats telling the user "still offline"
                    // when they can see their Wi-Fi icon.
                    if (ref.read(offlineStateProvider)) {
                      await Future<void>.delayed(const Duration(seconds: 2));
                      await connectivity.checkConnectivity();
                    }
                  }
                  await widget.onRefresh!();
                },
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Builder(
                  builder: (context) => widget.child(context),
                ),
              )
            : widget.child(context),
      ),
    );
  }
}
