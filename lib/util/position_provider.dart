import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';

enum PositionContext {
  first,
  middle,
  last,

  /// Alone in its row: rounded on both sides, the way a lone control should
  /// be rather than square on the side its missing neighbours would have had.
  single;

  bool get isFirst => this == first || this == single;
  bool get isLast => this == last || this == single;
}

class PositionProvider extends InheritedWidget {
  final PositionContext position;

  const PositionProvider({
    required this.position,
    required super.child,
    super.key,
  });

  static PositionContext? of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<PositionProvider>();
    return provider?.position;
  }

  @override
  bool updateShouldNotify(PositionProvider oldWidget) => position != oldWidget.position;
}

extension PositionProviderExtension on List<Widget> {
  List<Widget> withPositionProvider({BuildContext? context, TextDirection? textDirection}) {
    final resolvedDirection = textDirection ?? (context != null ? Directionality.of(context) : TextDirection.ltr);
    final firstIndex = resolvedDirection == TextDirection.rtl ? length - 1 : 0;
    final lastIndex = resolvedDirection == TextDirection.rtl ? 0 : length - 1;

    return mapIndexed(
      (index, e) => PositionProvider(
          position: length == 1
              ? PositionContext.single
              : index == firstIndex
                  ? PositionContext.first
                  : (index == lastIndex ? PositionContext.last : PositionContext.middle),
          child: Builder(
            builder: (context) => e,
          )),
    ).toList();
  }
}

class PositionRoundedClip extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final BorderRadius defaultRadius;

  const PositionRoundedClip({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.defaultRadius = const BorderRadius.all(Radius.circular(8)),
  });

  /// The corners a control in this position gets: the outer corners of the
  /// row's ends round, the corners between neighbours barely. For whatever
  /// draws inside the clip and wants to follow it - a focus ring, say.
  static BorderRadius radiusOf(
    BuildContext context, {
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(16)),
    BorderRadius defaultRadius = const BorderRadius.all(Radius.circular(8)),
  }) {
    final position = PositionProvider.of(context);
    return BorderRadius.only(
      topLeft: position?.isFirst ?? false ? borderRadius.topLeft : defaultRadius.topLeft,
      bottomLeft: position?.isFirst ?? false ? borderRadius.bottomLeft : defaultRadius.bottomLeft,
      topRight: position?.isLast ?? false ? borderRadius.topRight : defaultRadius.topRight,
      bottomRight: position?.isLast ?? false ? borderRadius.bottomRight : defaultRadius.bottomRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radiusOf(context, borderRadius: borderRadius, defaultRadius: defaultRadius),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}
