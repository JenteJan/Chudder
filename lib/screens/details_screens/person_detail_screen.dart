import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/providers/items/person_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_links_row.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/external_links.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

/// An actor, a director, anyone: who they are at the top and what they were
/// in underneath.
///
/// The top used to be a poster the size of the screen with three lines of
/// text beside it, and everything worth scrolling to was a screen down. It is
/// a header now: a round portrait, the name, the facts in a line, the sites
/// they are on, and their biography - the same shape as a film's page.
class PersonDetailScreen extends ConsumerStatefulWidget {
  final Person person;
  const PersonDetailScreen({required this.person, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  /// Which of the credits lends its backdrop, chosen once. It was shuffled
  /// on every build, so the page re-resolved a new picture each rebuild.
  final int _backdropPick = Random().nextInt(1 << 20);

  late final providerID = personDetailsProvider(widget.person.id);

  ImagesData? _backdropOf(List<ItemBaseModel> credits) =>
      credits.isEmpty ? null : credits[_backdropPick % credits.length].images;

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerID);
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final name = details?.name ?? widget.person.name;
    final image = details?.images?.primary ?? widget.person.image;
    final locale = context.localized.localeName;

    final facts = <String>[
      if (details?.dateOfBirth != null)
        context.localized.personBirthday(DateFormat.yMMMd(locale).format(details!.dateOfBirth!)),
      if (details?.dateOfDeath != null)
        context.localized.personDied(DateFormat.yMMMd(locale).format(details!.dateOfDeath!)),
      if (details?.age != null) context.localized.personAge(details!.age!),
      if (details?.birthPlace.isNotEmpty ?? false) context.localized.personBirthPlace(details!.birthPlace.join(", ")),
    ];

    return DetailScaffold(
      label: name,
      item: details,
      onRefresh: () async {
        await ref.read(providerID.notifier).fetchPerson(widget.person);
      },
      backDrops: _backdropOf([...?details?.movies, ...?details?.series]),
      content: (context, padding) => Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Into the backdrop's fade rather than below it, like every other
            // page.
            SizedBox(height: detailArtworkHeight(context) * (isPhone ? 0.6 : 0.45)),
            Padding(
              padding: padding,
              child: _PersonHeader(
                name: name,
                image: image,
                facts: facts,
                isPhone: isPhone,
                links: details == null ? const [] : details.externalLinks(),
                favourite: details?.userData.isFavourite ?? false,
                onFavourite: details == null
                    ? null
                    : () async =>
                        await ref.read(userProvider.notifier).setAsFavorite(!details.userData.isFavourite, details.id),
              ),
            ),
            if (details?.overview.summary.isNotEmpty ?? false)
              Padding(
                padding: padding.copyWith(top: 20),
                child: ExpandingText(text: details!.overview.summary),
              ),
            const SizedBox(height: 24),
            if (details?.movies.isNotEmpty ?? false)
              PosterRow(
                contentPadding: padding,
                posters: details?.movies ?? [],
                label: context.localized.mediaTypeMovie(details?.movies.length ?? 2),
              ),
            if (details?.series.isNotEmpty ?? false)
              PosterRow(
                contentPadding: padding,
                posters: details?.series ?? [],
                label: context.localized.mediaTypeSeries(details?.series.length ?? 2),
              ),
            if (details?.seerrMovies.isNotEmpty ?? false)
              SeerrPosterRow(
                contentPadding: padding,
                posters: details?.seerrMovies ?? [],
                label: context.localized.seerrMovies,
              ),
            if (details?.seerrSeries.isNotEmpty ?? false)
              SeerrPosterRow(
                contentPadding: padding,
                posters: details?.seerrSeries ?? [],
                label: context.localized.seerrSeries,
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  final String name;
  final ImageData? image;
  final List<String> facts;
  final bool isPhone;
  final List<ExternalLink> links;
  final bool favourite;
  final Future<void> Function()? onFavourite;

  const _PersonHeader({
    required this.name,
    required this.image,
    required this.facts,
    required this.isPhone,
    required this.links,
    required this.favourite,
    required this.onFavourite,
  });

  @override
  Widget build(BuildContext context) {
    final portraitSize = isPhone ? 150.0 : (MediaQuery.sizeOf(context).width * 0.16).clamp(160.0, 240.0);
    final portrait = SizedBox.square(
      dimension: portraitSize,
      child: PersonAvatar(person: Person(id: '', name: name, image: image)),
    );

    final text = Column(
      crossAxisAlignment: isPhone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: isPhone ? MainAxisAlignment.center : MainAxisAlignment.start,
          spacing: 12,
          children: [
            Flexible(
              child: SelectableText(
                name,
                textAlign: isPhone ? TextAlign.center : TextAlign.start,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SelectableIconButton(
              // The first thing a remote can press here, the way the play
              // button is on a film. Without it the page opened with nothing
              // selected.
              autofocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
              tooltip: favourite ? context.localized.removeAsFavorite : context.localized.addAsFavorite,
              onPressed: onFavourite,
              selected: favourite,
              backgroundColor: favourite ? const Color(0xFFE0304A) : null,
              iconColor: favourite ? Colors.white : null,
              selectedIcon: IconsaxPlusBold.heart,
              icon: IconsaxPlusLinear.heart,
            ),
            if (links.isNotEmpty) LinksMenuButton(links: links),
          ],
        ),
        if (facts.isNotEmpty)
          MetadataLabels(
            extraLabels: facts,
            alignment: isPhone ? WrapAlignment.center : WrapAlignment.start,
          ),
      ],
    );

    if (isPhone) {
      return Column(
        spacing: 16,
        children: [portrait, text],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 28,
      children: [
        portrait,
        Expanded(child: text),
      ],
    );
  }
}
