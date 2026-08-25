import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_card.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';

extension SeerrPosterShape on List<SeerrDashboardPosterModel> {
  /// The shape most of these posters are, worked out the way a row of local
  /// posters works out its own.
  ///
  /// It used to fall back to the layout's poster default, which is a constant
  /// and so took no notice of what was actually in the row. That agreed with
  /// the row above by coincidence whenever it held films or shows, and
  /// disagreed the moment it held one of the wider kinds.
  FladderItemType get dominantType {
    if (isEmpty) return FladderItemType.movie;

    final counts = <FladderItemType, int>{};
    for (final poster in this) {
      final type = switch (poster.type) {
        SeerrMediaType.movie => FladderItemType.movie,
        SeerrMediaType.tvshow => FladderItemType.series,
        SeerrMediaType.person => FladderItemType.person,
      };
      counts[type] = (counts[type] ?? 0) + 1;
    }

    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  double get dominantAspectRatio => dominantType.aspectRatio;
}

class SeerrPosterRow extends ConsumerWidget {
  final List<SeerrDashboardPosterModel> posters;
  final String label;
  final EdgeInsets contentPadding;
  final void Function(SeerrDashboardPosterModel focused)? onFocused;

  final void Function()? onLabelClick;

  /// The shape of a poster cell, when the row has to stand alongside rows
  /// of another kind. A details page sizes its portraits together — see the
  /// related row this one follows.
  final double? aspectRatio;

  const SeerrPosterRow({
    required this.posters,
    required this.label,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.onFocused,
    this.onLabelClick,
    this.aspectRatio,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dominantRatio = aspectRatio ?? posters.dominantAspectRatio;

    return HorizontalList<SeerrDashboardPosterModel>(
      contentPadding: contentPadding,
      label: label,
      autoFocus: ref.read(argumentsStateProvider).htpcMode ? FocusProvider.autoFocusOf(context) : false,
      onLabelClick: onLabelClick,
      dominantRatio: dominantRatio,
      items: posters,
      onFocused: (index) {
        if (onFocused != null) {
          onFocused?.call(posters[index]);
        } else {
          context.ensureVisible();
        }
      },
      itemBuilder: (context, index) {
        final poster = posters[index];
        return SeerrPosterCard(
          key: Key(poster.id),
          poster: poster,
          aspectRatio: dominantRatio,
        );
      },
    );
  }
}
