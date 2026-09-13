import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/screens/details_screens/person_detail_screen.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';
import 'package:chudder/widgets/shared/clickable_text.dart';
import 'package:chudder/widgets/shared/horizontal_list.dart';

/// The people in something, as a row of faces.
///
/// A face is round: a head shot cropped to a circle reads as a person where a
/// portrait rectangle reads as another poster, and on a page that is already
/// rows of posters the cast used to blend in with the films. Each card is as
/// wide as a poster card, so the row still lines up with the rows around it.
class PeopleRow extends ConsumerWidget {
  final List<Person> people;
  final EdgeInsets contentPadding;
  final Function()? onTap;
  const PeopleRow({
    required this.people,
    required this.contentPadding,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = posterCardMetrics(context, ref, artRatio: 1, maxLines: 2);

    return HorizontalList(
      label: people.any((e) => e.type != PersonKind.gueststar)
          ? context.localized.castAndCrew
          : context.localized.guestActor(people.length),
      height: metrics.height,
      dominantRatio: metrics.ratio,
      contentPadding: contentPadding,
      items: people,
      itemBuilder: (context, index) {
        final person = people[index];
        return PersonCard(
          person: person,
          aspectRatio: metrics.ratio,
          onTap: onTap ??
              () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PersonDetailScreen(
                        person: person,
                      ),
                    ),
                  ),
        );
      },
    );
  }
}

/// One person: a round picture, the name and the part they played.
class PersonCard extends StatefulWidget {
  final Person person;
  final double aspectRatio;
  final VoidCallback? onTap;

  const PersonCard({
    required this.person,
    required this.aspectRatio,
    this.onTap,
    super.key,
  });

  @override
  State<PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<PersonCard> {
  final ValueNotifier<bool> _highlight = ValueNotifier(false);
  bool _hovered = false;
  bool _focused = false;

  void _updateHighlight() => _highlight.value = _hovered || _focused;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    return FocusScale(
      highlight: _highlight,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: PersonAvatar(
                    person: person,
                    onTap: widget.onTap,
                    onHover: (hovering) {
                      _hovered = hovering;
                      _updateHighlight();
                    },
                    onFocusChanged: (focused) {
                      _focused = focused;
                      _updateHighlight();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ClickableText(
              text: person.name,
              maxLines: 1,
              highlight: _highlight,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            ClickableText(
              opacity: 0.55,
              text: person.role,
              maxLines: 1,
              highlight: _highlight,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round head shot, or the person's initials where there is none. Fills
/// whatever square it is given.
class PersonAvatar extends StatelessWidget {
  final Person person;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChanged;

  const PersonAvatar({
    required this.person,
    this.onTap,
    this.onHover,
    this.onFocusChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FocusButton(
      onTap: onTap,
      onHover: onHover,
      onFocusChanged: onFocusChanged,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceContainer,
          border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: FladderImage(
          image: person.image,
          fit: BoxFit.cover,
          // A head shot is a portrait, and a circle cut from its top cropped
          // the chin off nearly everyone. A little way down keeps the whole
          // face without sliding into the collar.
          alignment: const Alignment(0, -0.55),
          placeHolder: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  person.name.getInitials(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface.withValues(alpha: 0.8),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
