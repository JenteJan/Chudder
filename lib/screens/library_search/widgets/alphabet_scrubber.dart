import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/shared/focus_ring.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';

/// The letters of the alphabet down the edge of a grid: pick one and the grid
/// narrows to titles that start with it.
///
/// A filter rather than a scroll: the library arrives in pages, so there is
/// often no "M" on the screen yet to scroll to, and asking the server for the
/// Ms is both exact and instant. The strip shrinks to fit whatever height it
/// is given, a finger can drag along it with the letter shown large beside the
/// thumb, and on a phone it only appears while the grid is moving, so it is
/// never in the way of the posters.
/// Every strip that is mounted, oldest first. Every Home tab keeps its pages,
/// so the Search tab's strip, a library's and a collection's are all alive at
/// once; one variable held whichever mounted last, and the Search tab's grid
/// handed the selection to a strip on another tab - or to nothing, once that
/// one was disposed and the variable cleared.
final List<FocusNode> _strips = [];

/// The strip on the page [from] is on, if that page has one: for a press off
/// the right edge of a grid to land on. Its page is the one whose scope [from]
/// sits under.
FocusNode? alphabetScrubberNodeFor(FocusNode from) {
  final ancestors = from.ancestors.toSet();
  for (final strip in _strips.reversed) {
    if (strip.context?.mounted != true) continue;
    final scope = strip.enclosingScope;
    if (scope != null && ancestors.contains(scope)) return strip;
  }
  return null;
}

class AlphabetScrubber extends StatefulWidget {
  /// The letter the grid is narrowed to, `#` for titles that start with a
  /// digit or symbol, null for all of them.
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// The grid's own controller, watched so the strip can hide itself on a
  /// phone while nothing is moving.
  final ScrollController? scrollController;

  const AlphabetScrubber({
    required this.selected,
    required this.onSelected,
    this.scrollController,
    super.key,
  });

  static const List<String> letters = [
    '#',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', //
  ];

  @override
  State<AlphabetScrubber> createState() => _AlphabetScrubberState();
}

/// The strip's own room above and below the letters, and its rim.
const double _stripPadding = 4;
const double _stripBorder = 1;

class _AlphabetScrubberState extends State<AlphabetScrubber> {
  /// The letter under the finger while dragging, shown large beside the strip.
  String? _dragging;

  /// The strip as a whole, for a remote to land on; once it has, the letters
  /// inside take over.
  final FocusNode _stripNode = FocusNode(debugLabel: 'alphabetScrubber');

  /// Whether the strip is shown on a phone: while scrolling, while a letter
  /// is active, and for a moment after either.
  bool _revealed = false;
  Timer? _hideTimer;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    _strips.add(_stripNode);
  }

  @override
  void didUpdateWidget(covariant AlphabetScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
    if (oldWidget.selected != widget.selected) _reveal();
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    _hideTimer?.cancel();
    _strips.remove(_stripNode);
    _stripNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    final offset = controller.offset;
    if ((offset - _lastOffset).abs() < 2) return;
    _lastOffset = offset;
    _reveal();
  }

  void _reveal() {
    if (!mounted) return;
    if (!_revealed) setState(() => _revealed = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _dragging == null) setState(() => _revealed = false);
    });
  }

  String _letterAt(double dy, double itemHeight) {
    final index = (dy / itemHeight).floor().clamp(0, AlphabetScrubber.letters.length - 1);
    return AlphabetScrubber.letters[index];
  }

  void _pick(String letter) {
    widget.onSelected(widget.selected == letter ? null : letter);
  }

  @override
  Widget build(BuildContext context) {
    final input = AdaptiveLayout.inputDeviceOf(context);
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final colors = Theme.of(context).colorScheme;
    final onlyWhileScrolling = isPhone && input == InputDevice.touch;
    final visible = !onlyWhileScrolling || _revealed || widget.selected != null || _dragging != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Every letter gets an equal share of the height left once the strip's
        // own padding and border have had theirs, never taller than a
        // comfortable tap and never so short the label stops being readable.
        final count = AlphabetScrubber.letters.length;
        const chrome = 2 * (_stripPadding + _stripBorder);
        final itemHeight = ((constraints.maxHeight - chrome) / count).clamp(11.0, 22.0);
        final fontSize = (itemHeight * 0.62).clamp(8.0, 12.5);
        final compact = itemHeight < 16;
        final stripHeight = itemHeight * count;

        Widget letterTile(String letter) {
          final selected = widget.selected == letter;
          final underFinger = _dragging == letter;
          return SizedBox(
            height: itemHeight,
            width: compact ? 18 : 22,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: selected || underFinger ? (compact ? 16 : 20) : 0,
                height: selected || underFinger ? (compact ? 16 : 20) : 0,
                // The letter under the pad or the finger wears the selection
                // colour, inverted like a chip; the letter the list is on
                // wears the primary. When they are the same letter the
                // selection wins the fill and the primary becomes a rim, so
                // the pad arriving on the active letter is still a change.
                decoration: BoxDecoration(
                  color: underFinger ? focusRingColor(colors) : colors.primary,
                  border: underFinger && selected ? Border.all(width: 2, color: colors.primary) : null,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }

        Widget letterLabel(String letter) {
          final selected = widget.selected == letter;
          final underFinger = _dragging == letter;
          return SizedBox(
            height: itemHeight,
            width: compact ? 18 : 22,
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1,
                  fontWeight: selected || underFinger ? FontWeight.w800 : FontWeight.w600,
                  color: underFinger
                      ? focusRingEdgeColor(colors)
                      : selected
                          ? colors.onPrimary
                          : colors.onSurface.withValues(alpha: widget.selected == null ? 0.7 : 0.4),
                ),
              ),
            ),
          );
        }

        final strip = Container(
          padding: const EdgeInsets.symmetric(vertical: _stripPadding, horizontal: 2),
          decoration: BoxDecoration(
            color: colors.surfaceContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(width: _stripBorder, color: colors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: SizedBox(
            height: stripHeight,
            child: Stack(
              children: [
                Column(children: AlphabetScrubber.letters.map(letterTile).toList()),
                // A pointer picks one letter at a time; a finger slides.
                if (input == InputDevice.touch)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (details) =>
                        setState(() => _dragging = _letterAt(details.localPosition.dy, itemHeight)),
                    onVerticalDragUpdate: (details) {
                      final letter = _letterAt(details.localPosition.dy, itemHeight);
                      if (letter != _dragging) setState(() => _dragging = letter);
                    },
                    onVerticalDragEnd: (_) {
                      final letter = _dragging;
                      setState(() => _dragging = null);
                      if (letter != null) _pick(letter);
                      _reveal();
                    },
                    onTapUp: (details) => _pick(_letterAt(details.localPosition.dy, itemHeight)),
                    child: Column(children: AlphabetScrubber.letters.map(letterLabel).toList()),
                  )
                else
                  FocusTraversalGroup(
                    policy: _ScrubberFocusPolicy(_stripNode),
                    child: Focus(
                      focusNode: _stripNode,
                      // Landing on the strip lands on its active letter, or
                      // the first one.
                      onFocusChange: (focused) {
                        if (!focused || !_stripNode.hasPrimaryFocus) return;
                        final letters = AlphabetScrubber.letters;
                        final target = widget.selected == null ? 0 : letters.indexOf(widget.selected!);
                        final nodes = _stripNode.traversalDescendants.toList();
                        if (nodes.isNotEmpty) nodes[target.clamp(0, nodes.length - 1)].requestFocus();
                      },
                      child: Column(
                        children: AlphabetScrubber.letters
                            .map(
                              (letter) => _LetterButton(
                                onTap: () => _pick(letter),
                                onHover: (hovering) => setState(() => _dragging = hovering ? letter : null),
                                child: letterLabel(letter),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        final preview = _dragging ?? widget.selected;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: visible ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 10,
              children: [
                // The letter under the finger, large enough to read past the
                // finger that is covering the strip.
                if (input == InputDevice.touch)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dragging != null ? 1 : 0,
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        preview ?? '',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: colors.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: widget.selected == null
                      ? context.localized.filterByLetter
                      : '${context.localized.filterByLetter}: ${widget.selected}',
                  child: strip,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LetterButton extends StatelessWidget {
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;
  final Widget child;

  const _LetterButton({required this.onTap, required this.onHover, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onHover: onHover,
      onFocusChange: onHover,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
  }
}

/// Up and down walk the letters and stop at the ends; left goes back to
/// whatever in the grid the selection came from, or to the card beside the
/// letter; right is the edge of the page.
///
/// The letters only, by their own order. Handed to Flutter's directional
/// search, down from a letter near the top of the strip weighed everything
/// below it on the page, and the poster-size slider - which ends under the
/// strip on a desktop window - was nearer than the next letter. Its ring on a
/// thin bar at the right edge looked like a scrollbar that had taken the
/// selection, and down from there was the grid.
class _ScrubberFocusPolicy extends WidgetOrderTraversalPolicy {
  final FocusNode strip;

  _ScrubberFocusPolicy(this.strip);

  // Flutter's own search is deliberately never asked - see the class note.
  @override
  // ignore: must_call_super
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.left:
        final back = lastMainFocus;
        if (back != null && back.canRequestFocus && isLiveFocusNode(back)) {
          back.requestFocus();
          return true;
        }
        // Nothing remembered, or it has scrolled away: the nearest card on
        // this letter's own line.
        horizontalNeighbour(currentNode, direction, towardsSidebar: true)?.requestFocus();
        return true;
      case TraversalDirection.right:
        return true;
      case TraversalDirection.up || TraversalDirection.down:
        final letters = strip.traversalDescendants.where(isLiveFocusNode).toList()
          ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
        final index = letters.indexOf(currentNode);
        if (index == -1) return true;
        final next = direction == TraversalDirection.up ? index - 1 : index + 1;
        if (next >= 0 && next < letters.length) letters[next].requestFocus();
        return true;
    }
  }
}
