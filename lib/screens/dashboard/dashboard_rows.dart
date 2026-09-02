import 'package:flutter/material.dart';

import 'package:fladder/util/focus_provider.dart';

/// The dashboard's rows, built only as they come into view.
///
/// Each used to be its own [SliverToBoxAdapter], which is not lazy: every row
/// - a dozen and more, one per library - was built and laid out on the first
/// frame, and each of those set its own pictures loading. A row that is a
/// screen or two down is now built when it is nearly there, which is what a
/// list is for.
class DashboardRows extends StatelessWidget {
  const DashboardRows({
    required this.rows,
    required this.spacing,
    this.autoFocusFirst = true,
    super.key,
  });

  final List<Widget> rows;
  final double spacing;

  /// Whether the first row takes focus; the dashboard hands that to its
  /// banner when it has one.
  final bool autoFocusFirst;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      itemCount: rows.length,
      itemBuilder: (context, index) => FocusProvider(
        autoFocus: autoFocusFirst && index == 0,
        child: rows[index],
      ),
      separatorBuilder: (context, index) => SizedBox(height: spacing),
    );
  }
}
