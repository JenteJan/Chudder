import 'package:flutter/material.dart';

/// Shows a [RefreshIndicator]'s refresh even while one is already running.
///
/// [RefreshIndicatorState.show] does nothing while the indicator is up, so a
/// refresh asked for during another was lost: on a big library the page's
/// first load runs for seconds while the filter lists come in behind the
/// posters, and a chip changed in that window - easy, now that its panel
/// opens on hover - left the chip reading Random and the grid in the order
/// it had, with the next page in the new one.
///
/// Count each run where it starts, with [started] at the top of the
/// indicator's onRefresh; [show] then waits out a run already going and
/// starts another. Several asks during one run start one more, not one each.
class RefreshAgain {
  int _runs = 0;

  /// Call first thing in the indicator's onRefresh.
  void started() => _runs++;

  /// Starts a refresh of [indicator] once no other is running. Returns when
  /// that refresh is done, or as soon as [mounted] says the page has gone.
  Future<void> show(
    RefreshIndicatorState? Function() indicator, {
    required bool Function() mounted,
  }) async {
    final before = _runs;
    while (mounted() && _runs == before) {
      final state = indicator();
      if (state == null) return;
      await state.show();
      // Dropped: the run that was going has finished, but the indicator is
      // still on its way out and drops another show() until it has gone.
      if (_runs == before) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
