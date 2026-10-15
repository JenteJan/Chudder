// A d-pad check for any screen, dialog or panel: open it the way a remote
// would see it, walk every arrow from every stop the arrows reach, and fail
// on each control on screen that a remote can never get to.
//
// Usage:
//   await pumpDpad(tester, child: ...);            // or openDpad(tester, (context) => showX(context))
//   final walk = await walkDpad(tester);
//   walk.expectStartsInside(find.byType(MyDialog));
//   walk.expectAllReachable(within: find.byType(MyDialog));
//
// "Control" means anything pressable: buttons, list tiles, chips, cards
// (InkWell / InkResponse), text fields, checkboxes, switches, radios and
// sliders - enabled, laid out and on screen. A control that deliberately takes
// no focus (an InkWell with canRequestFocus: false, the way a card leaves it
// to its own button) is not counted.

import 'dart:collection' show Queue;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/poster_defaults.dart';

const tvSize = Size(1920, 1080);

AdaptiveLayoutModel dpadLayout(Size size) => AdaptiveLayoutModel(
      viewSize: size.width < 600 ? ViewSize.phone : (size.width >= 1920 ? ViewSize.desktop : ViewSize.tablet),
      layoutMode: size.width < 600 ? LayoutMode.single : LayoutMode.dual,
      inputDevice: InputDevice.dPad,
      platform: TargetPlatform.android,
      isDesktop: false,
      posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
      controller: const {},
      sideBarWidth: 0,
      topBarHeight: 0,
      statusBarHeight: 0,
    );

/// The app's dark theme, its strings and a d-pad as the input, around [child].
Widget dpadApp({required Widget child, List<Override> overrides = const [], Size size = tvSize}) {
  final theme = FladderTheme.theme(FladderTheme.defaultScheme(Brightness.dark), DynamicSchemeVariant.tonalSpot);
  return ProviderScope(
    overrides: overrides,
    child: AdaptiveLayout(
      data: dpadLayout(size),
      child: MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Shows [child] on a television-sized screen with a d-pad in hand.
Future<void> pumpDpad(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size size = tvSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(dpadApp(child: child, overrides: overrides, size: size));
  await _settle(tester);
}

/// Opens what [open] opens - a dialog, a sheet - over an empty page, as a
/// remote user would meet it.
Future<void> openDpad(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  List<Override> overrides = const [],
  Size size = tvSize,
}) async {
  late BuildContext pageContext;
  await pumpDpad(
    tester,
    overrides: overrides,
    size: size,
    // A Consumer, so the context handed to [open] is a WidgetRef as well,
    // for the helpers that want one.
    child: Consumer(builder: (context, ref, _) {
      pageContext = context;
      return const SizedBox.expand();
    }),
  );
  open(pageContext);
  await _settle(tester);
  await _settle(tester);
}

final _arrows = {
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
};

class DpadWalk {
  DpadWalk._(this.start, this.reached, this.moves, [this.reachedLabels = const {}]);

  /// The controls reached, by what they say - for a control rebuilt after
  /// the walk passed it (a row of pills redrawn when one is chosen).
  final Set<String> reachedLabels;

  /// Where the focus was before any key was pressed.
  final FocusNode? start;

  /// Every node the arrows reached, the start included.
  final Set<FocusNode> reached;

  /// "from --dir--> to", for messages.
  final List<String> moves;

  Set<Element> get _reachedAncestors {
    final ancestors = <Element>{};
    for (final node in reached) {
      final context = node.context;
      if (context == null || !context.mounted) continue;
      final element = context as Element;
      ancestors.add(element);
      element.visitAncestorElements((ancestor) {
        ancestors.add(ancestor);
        return true;
      });
    }
    return ancestors;
  }

  /// The pressable controls under [within] that the walk never reached.
  List<String> unreached(Finder within) {
    final reachedElements = _reachedAncestors;
    final missing = <String>[];
    for (final root in within.evaluate()) {
      void visit(Element element) {
        if (_isControl(element) &&
            _onScreen(element) &&
            !reachedElements.contains(element) &&
            !_insideReachedStop(element) &&
            !_reachedByLabel(element)) {
          missing.add(describeControl(element));
        }
        element.visitChildElements(visit);
      }

      visit(root);
    }
    return missing;
  }

  bool _reachedByLabel(Element element) {
    final label = describeControl(element);
    if (label.endsWith('(no label)')) {
      // An unnamed ink inside a named stop: reached with that stop.
      Element? named;
      element.visitAncestorElements((ancestor) {
        if (_isControl(ancestor)) named = ancestor;
        return named == null;
      });
      return named != null && reachedLabels.contains(describeControl(named!));
    }
    return reachedLabels.contains(label);
  }

  /// A control whose focus is a stop around it - a card's own ink inside the
  /// card's focus - is pressed through that stop.
  bool _insideReachedStop(Element element) {
    final reachedContexts = {for (final node in reached) node.context};
    var inside = false;
    element.visitAncestorElements((ancestor) {
      if (reachedContexts.contains(ancestor)) {
        inside = true;
        return false;
      }
      // Another focusable thing in between: that one would be the stop.
      return !(ancestor.widget is Focus &&
          (ancestor.widget as Focus).canRequestFocus != false &&
          ancestor.widget is! FocusScope);
    });
    return inside;
  }

  void expectStartsInside(Finder within) {
    final context = start?.context;
    final inside = context != null &&
        within.evaluate().any((root) {
          var found = identical(root, context);
          (context as Element).visitAncestorElements((ancestor) {
            if (identical(ancestor, root)) found = true;
            return !found;
          });
          return found;
        });
    expect(inside, isTrue, reason: 'Nothing inside was focused when it opened (focus: ${start?.debugLabel ?? start}).');
  }

  void expectAllReachable({required Finder within, Set<String> except = const {}}) {
    final missing = unreached(within).where((label) => !except.any(label.contains)).toList();
    expect(missing, isEmpty, reason: 'Out of a remote\'s reach:\n  ${missing.join('\n  ')}');
  }
}

bool _isControl(Element element) {
  final widget = element.widget;
  return switch (widget) {
    InkResponse(:final onTap, :final onLongPress, :final canRequestFocus) =>
      (onTap != null || onLongPress != null) && canRequestFocus,
    EditableText() => true,
    Checkbox(:final onChanged) => onChanged != null,
    Switch(:final onChanged) => onChanged != null,
    Slider(:final onChanged) => onChanged != null,
    FocusButton(:final onTap, :final onLongPress) => onTap != null || onLongPress != null,
    _ => false,
  };
}

bool _onScreen(Element element) {
  final render = element.renderObject;
  if (render is! RenderBox || !render.attached || !render.hasSize || render.size.isEmpty) return false;
  // Inside an ExcludeFocus that is excluding: deliberately out of reach.
  var excluded = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is ExcludeFocus && widget.excluding) excluded = true;
    if (widget is Offstage && widget.offstage) excluded = true;
    if (widget is Visibility && !widget.visible) excluded = true;
    return !excluded;
  });
  if (excluded) return false;
  final box = render.localToGlobal(Offset.zero) & render.size;
  final screen = Offset.zero & (element.findAncestorWidgetOfExactType<MediaQuery>()?.data.size ?? tvSize);
  // Below the fold of a list counts: a remote scrolls to it.
  return box.overlaps(screen) || box.top >= screen.top;
}

/// A control as a person would name it: its words, its tooltip, or its type.
String describeControl(Element element) {
  final words = <String>[];
  void collect(Element child) {
    final widget = child.widget;
    if (widget is Text && widget.data != null) words.add(widget.data!);
    if (widget is RichText) words.add(widget.text.toPlainText());
    if (widget is Tooltip && widget.message != null) words.add('[${widget.message}]');
    if (widget is Icon && widget.icon != null) words.add('<icon ${widget.icon!.codePoint.toRadixString(16)}>');
    if (words.length < 3) child.visitChildElements(collect);
  }

  collect(element);
  String? tooltip;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Tooltip) tooltip = widget.message;
    return tooltip == null && ancestor.widget is! Material;
  });
  final label = [if (tooltip != null) '[$tooltip]', ...words.take(3)].join(' ');
  return '${element.widget.runtimeType}: ${label.isEmpty ? '(no label)' : label}';
}

/// Walks every arrow from every stop reachable from the current focus.
Future<DpadWalk> walkDpad(WidgetTester tester, {int maxStops = 250}) async {
  final start = FocusManager.instance.primaryFocus;
  final reached = <FocusNode>{};
  final moves = <String>[];
  final labels = <String>{};
  void label(FocusNode node) {
    final context = node.context;
    if (context == null) return;
    final element = context as Element;
    if (_isControl(element)) labels.add(describeControl(element));
    element.visitAncestorElements((ancestor) {
      if (_isControl(ancestor)) {
        labels.add(describeControl(ancestor));
        return false;
      }
      return true;
    });
  }

  if (start == null) return DpadWalk._(null, reached, moves);
  reached.add(start);
  label(start);
  final queue = Queue<FocusNode>()..add(start);
  // Twice over: the walk itself changes things - a slider moved by left and
  // right enables "clear changes" beside it - and what came alive after its
  // neighbours were tried is only found on a second round.
  var round = 0;
  while (round < 2) {
    if (queue.isEmpty) {
      if (++round == 2) break;
      queue.addAll(reached.where((node) => node.context != null));
    }
    if (reached.length >= maxStops) break;
    final node = queue.removeFirst();
    for (final arrow in _arrows.entries) {
      if (node.context == null || !node.canRequestFocus) break;
      // Asked again until it stays: a press before may still be moving the
      // selection on a frame or two later.
      for (var attempt = 0; attempt < 4 && !node.hasPrimaryFocus; attempt++) {
        if (node.context == null || !node.canRequestFocus) break;
        node.requestFocus();
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      if (!node.hasPrimaryFocus) continue;
      // Each press as if arriving fresh: the directional policy remembers the
      // way it came and walks back along it on an opposite press, which a
      // jump made here would otherwise turn into a press that goes nowhere.
      final scope = node.nearestScope;
      final context = node.context;
      if (scope != null && context != null) FocusTraversalGroup.maybeOf(context)?.invalidateScopeData(scope);
      await tester.sendKeyEvent(arrow.key);
      // A few frames: some presses move the selection again a frame later
      // (a season switched re-parks it on the playing episode).
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      final next = FocusManager.instance.primaryFocus;
      if (next == null || identical(next, node)) {
        moves.add('${_name(node)} --${arrow.value}--> ${next == null ? 'nothing' : '(stays)'}');
        continue;
      }
      moves.add('${_name(node)} --${arrow.value}--> ${_name(next)}');
      label(next);
      if (reached.add(next)) queue.add(next);
    }
  }
  return DpadWalk._(start, reached, moves, labels);
}

String _name(FocusNode node) {
  final context = node.context;
  if (context == null) return node.debugLabel ?? '$node';
  Element? control;
  (context as Element).visitAncestorElements((ancestor) {
    if (_isControl(ancestor)) control = ancestor;
    return control == null;
  });
  final rect = context.findRenderObject() is RenderBox
      ? (() {
          final box = context.findRenderObject() as RenderBox;
          final at = box.localToGlobal(Offset.zero);
          return '@${at.dx.round()},${at.dy.round()}';
        })()
      : '';
  return '${control == null ? (node.debugLabel ?? node.runtimeType) : describeControl(control!)} $rect';
}

/// The focusable node of the control [control] finds: the outermost one
/// inside it - a list tile's own, not that of a button at its end.
FocusNode focusNodeIn(Finder control) {
  final root = control.evaluate().first;
  int? depth(FocusNode node) {
    final context = node.context;
    if (context == null) return null;
    if (identical(context, root)) return 0;
    var steps = 0;
    var found = false;
    (context as Element).visitAncestorElements((ancestor) {
      steps++;
      found = identical(ancestor, root);
      return !found;
    });
    return found ? steps : null;
  }

  FocusNode? best;
  int? bestDepth;
  for (final node in FocusManager.instance.rootScope.descendants) {
    if (!node.canRequestFocus || node.skipTraversal) continue;
    final d = depth(node);
    if (d != null && (bestDepth == null || d < bestDepth)) {
      best = node;
      bestDepth = d;
    }
  }
  return best ?? (throw StateError('Nothing focusable inside $control'));
}

bool _isInside(FocusNode? node, Finder target) {
  final context = node?.context;
  if (context == null) return false;
  return target.evaluate().any((root) {
    if (identical(root, context)) return true;
    var found = false;
    (context as Element).visitAncestorElements((ancestor) {
      found = identical(ancestor, root);
      return !found;
    });
    return found;
  });
}

/// From the control [from], [key] lands inside [to].
Future<void> expectPress(
  WidgetTester tester, {
  required Finder from,
  required LogicalKeyboardKey key,
  required Finder to,
}) async {
  final node = focusNodeIn(from);
  node.requestFocus();
  await tester.pump();
  final scope = node.nearestScope;
  if (scope != null && node.context != null) {
    FocusTraversalGroup.maybeOf(node.context!)?.invalidateScopeData(scope);
  }
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 300));
  final now = FocusManager.instance.primaryFocus;
  expect(_isInside(now, to), isTrue,
      reason: '${key.keyLabel} from ${describeControl(from.evaluate().first)} went to '
          '${now == null ? 'nothing' : _name(now)}');
}
