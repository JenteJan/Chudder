import 'package:flutter/material.dart';

/// A [Hero] whose child keeps its focus node through the flight.
///
/// For the length of a hero flight the hero on the page that is not moving -
/// the card a details page was opened from, on the push and again on the pop
/// - is swapped for a placeholder. Flutter's own placeholder is an empty box,
/// which takes the card's button out of the tree; and a button leaving the
/// tree takes its focus node with it, which drops it from the scope's list of
/// recently focused nodes. So when the route settles and the scope is asked
/// for its focused child, it answers with the card *before* the one that was
/// opened - the one you moved down from - and the page scrolls to that row
/// before the observer puts the selection right and scrolls it back. Twice
/// over: once as the pop begins, once as the transition ends.
///
/// A placeholder that still holds the card is not enough either: hero,
/// placeholder and card are three widgets where there were two, and the card
/// is built again as a new element under the new parent. Same widget, new
/// state, new node, same loss. The card is keyed with a [GlobalKey] instead,
/// so that it is *moved* under the placeholder and back rather than rebuilt,
/// and its node is never out of the tree at all.
class FocusHero extends StatefulWidget {
  final Object tag;
  final Widget child;

  const FocusHero({required this.tag, required this.child, super.key});

  @override
  State<FocusHero> createState() => _FocusHeroState();
}

class _FocusHeroState extends State<FocusHero> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tag,
      // The same box, still holding the card - moved here by its key -
      // hidden and not ticking while the copy in the overlay flies.
      placeholderBuilder: (context, size, child) => SizedBox(
        width: size.width,
        height: size.height,
        child: Offstage(child: TickerMode(enabled: false, child: child)),
      ),
      child: KeyedSubtree(key: _keep, child: widget.child),
    );
  }
}
