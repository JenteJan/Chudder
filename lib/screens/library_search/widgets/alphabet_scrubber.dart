import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
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
/// The strip on screen, if one is, for a press off the right edge of a grid
/// to land on. Held by the strip while it is mounted.
FocusNode? alphabetScrubberNode;

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
    alphabetScrubberNode = _stripNode;
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
    if (identical(alphabetScrubberNode, _stripNode)) alphabetScrubberNode = null;
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
        // Every letter gets an equal share of the height, never taller than a
        // comfortable tap and never so short the label stops being readable.
        final count = AlphabetScrubber.letters.length;
        final itemHeight = (constraints.maxHeight / count).clamp(11.0, 22.0);
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
                decoration: BoxDecoration(
                  color: selected ? colors.primary : colors.primaryContainer,
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
                  color: selected
                      ? colors.onPrimary
                      : underFinger
                          ? colors.onPrimaryContainer
                          : colors.onSurface.withValues(alpha: widget.selected == null ? 0.7 : 0.4),
                ),
              ),
            ),
          );
        }

        final strip = Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: colors.surfaceContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
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
                    policy: _ScrubberFocusPolicy(),
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

/// Up and down walk the letters; left goes back to whatever in the grid the
/// selection came from.
class _ScrubberFocusPolicy extends WidgetOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      final back = lastMainFocus;
      if (back != null && back.canRequestFocus && back.context?.mounted == true) {
        back.requestFocus();
        return true;
      }
    }
    if (direction == TraversalDirection.right) return true;
    return super.inDirection(currentNode, direction);
  }
}
