import 'package:flutter/material.dart';

/// Loading indicators a person can actually see right now: an indeterminate
/// [ProgressIndicator] or one of [names] (the app's own placeholders), laid
/// out, painted by every ancestor, ticking, and on screen.
///
/// Walks the element tree, so it is only asked when everything else already
/// says the step is done.
List<String> visibleLoadingIndicators(Set<String> names, {int limit = 5}) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return const [];
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  final found = <String>[];

  void visit(Element element) {
    if (found.length >= limit) return;
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is TickerMode && !widget.enabled) return;
    // Hidden without being offstage: what IndexedStack does to the children
    // it is not showing. Its render object paints nothing but does not say so
    // through paintsChild.
    if (widget is Visibility && !widget.visible) return;
    if (widget is SliverVisibility && !widget.visible) return;
    final isIndicator =
        (widget is ProgressIndicator && widget.value == null) || names.contains(widget.runtimeType.toString());
    if (isIndicator) {
      if (_isVisible(element, screen)) found.add(widget.runtimeType.toString());
      return;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

bool _isVisible(Element element, Rect screen) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) return false;
  if (renderObject.size.isEmpty) return false;
  RenderObject child = renderObject;
  var parent = child.parent;
  while (parent != null) {
    if (!parent.paintsChild(child)) return false;
    child = parent;
    parent = child.parent;
  }
  final rect = MatrixUtils.transformRect(renderObject.getTransformTo(null), Offset.zero & renderObject.size);
  return rect.overlaps(screen);
}
