import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/util/refresh_state.dart';

/// How long a first load may take before the indicator comes down to say so.
///
/// A first load used to go through [RefreshIndicatorState.show]: the spinner
/// snapped down for 150ms before the request was even sent, and then stayed on
/// screen, fading out, for a good while after the page had everything. On a
/// load that takes a tenth of a second that was a spinner flashing over a page
/// that was already there. Now the load starts at once and the indicator only
/// appears for one that is still going after this long.
const Duration kRefreshIndicatorDelay = Duration(milliseconds: 300);

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

/// A load that starts now, rather than after the indicator's snap.
extension RefreshIndicatorLoad on GlobalKey<RefreshIndicatorState> {
  /// Runs the refresh of the [PullToRefresh] this key belongs to straight
  /// away, and shows the indicator only if it is still running after
  /// [kRefreshIndicatorDelay]. Anything that asks the indicator for a refresh
  /// meanwhile joins this one instead of starting a second.
  ///
  /// For a page's first load. A refresh somebody asked for - a pull, F5, a
  /// changed filter - should still [RefreshIndicatorState.show], so they see
  /// it happen.
  Future<void> load() {
    final pullToRefresh = currentContext?.findAncestorStateOfType<_PullToRefreshState>();
    if (pullToRefresh == null) return currentState?.show() ?? Future<void>.value();
    return pullToRefresh.load();
  }
}

class _PullToRefreshState extends ConsumerState<PullToRefresh> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final FocusNode focusNode = FocusNode();

  /// The load [load] started, until it is done and no indicator it brought
  /// down is still waiting to hear so.
  Future<void>? _load;
  Timer? _indicatorTimer;
  bool _indicatorOwed = false;

  GlobalKey<RefreshIndicatorState> get refreshKey {
    return (widget.refreshKey ?? _refreshIndicatorKey);
  }

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnStart) {
      // A microtask, so the page this sits in has been built and laid out -
      // and is not being built - when the load writes to its providers.
      Future.microtask(() {
        if (mounted) load();
      });
    }
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    super.dispose();
  }

  Future<void> load() {
    final existing = _load;
    if (existing != null) return existing;
    if (widget.onRefresh == null) return Future<void>.value();

    final future = _refresh();
    _load = future;
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(kRefreshIndicatorDelay, () {
      if (!mounted || !identical(_load, future)) return;
      final indicator = refreshKey.currentState;
      if (indicator == null) return;
      // The indicator calls back into [_onIndicatorRefresh] once it has
      // snapped down, which may be after the load has finished: [_load] stays
      // until then, so what it gets is this load and not a second one.
      _indicatorOwed = true;
      indicator.show().whenComplete(() {
        _indicatorOwed = false;
        if (identical(_load, future)) _load = null;
      });
    });
    future.whenComplete(() {
      _indicatorTimer?.cancel();
      if (!_indicatorOwed && identical(_load, future)) _load = null;
    });
    return future;
  }

  Future<void> _onIndicatorRefresh() => _load ?? _refresh();

  // A manual refresh is an explicit "try again". While the app believes it is
  // offline it stops talking to the server, so without this the pull did
  // nothing and the user had to wait for the 10s recheck timer to notice the
  // connection is back.
  Future<void> _refresh() async {
    // Both reads happen before the first await. `ref` throws once this widget
    // is disposed, and a refresh that started while the user was on their way
    // somewhere else came back to a dead element - which is a real crash, not
    // a lost refresh. The connectivity provider is keepAlive, so the notifier
    // stays usable regardless of what happened to this widget.
    final connectivity = ref.read(connectivityStatusProvider.notifier);
    if (ref.read(offlineStateProvider)) {
      await connectivity.checkConnectivity();
      // Right after reconnecting, the first probe can lose the race against
      // the radio coming back up. One retry inside the same gesture beats
      // telling the user "still offline" when they can see their Wi-Fi icon.
      if (mounted && ref.read(offlineStateProvider)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await connectivity.checkConnectivity();
      }
    }
    if (!mounted) return;
    await widget.onRefresh!();
  }

  @override
  Widget build(BuildContext context) {
    // Reload on either transition. Coming back online, nothing reloads by
    // itself - the banner clears but the content stays stale until a manual
    // pull. Going offline is the same problem pointing the other way: the
    // screen keeps showing server content that cannot be opened any more,
    // when what it should show is whatever is on disk.
    ref.listen<bool>(offlineStateProvider, (previous, next) {
      if (previous == null || previous == next) return;
      refreshKey.currentState?.show();
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
                onRefresh: _onIndicatorRefresh,
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
