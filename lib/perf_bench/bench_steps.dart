import 'dart:async';
import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/perf_bench/perf_bench_io.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/auth_provider.dart';
import 'package:chudder/providers/router_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/login/lock_screen.dart';

/// What a step did once it was set off.
class Performed {
  Performed({this.error, this.condition, this.measureFromUs, this.readyUs, this.detectedUs, this.extra = const {}});

  final String? error;

  /// Extra readiness condition for the detector: a reason to keep waiting, or
  /// null once it holds.
  final String? Function()? condition;

  /// When the step's timer starts, if not when it was performed (typing is
  /// timed from the submit, not the first key).
  final int? measureFromUs;

  /// Set by steps with a readiness signal of their own (the player): the
  /// moment it became ready, and the moment that was seen.
  final int? readyUs;
  final int? detectedUs;

  /// More numbers for the output; ints are monotonic microseconds and are
  /// reported as milliseconds from the step's start.
  final Map<String, Object?> extra;
}

class PreparedStep {
  PreparedStep(this.perform, {this.error});
  PreparedStep.failed(String this.error) : perform = _noop;

  final Future<Performed> Function() perform;
  final String? error;

  static Future<Performed> _noop() async => Performed();
}

/// The actions a scenario is made of. Each one goes through the same code the
/// app runs when a person does it - the router, a card's `navigateTo`, the
/// search field's own input handling, a pointer tap on the widget - with no
/// input injected into Windows.
///
/// To add an action: a case in [prepare] that does any untimed setup and
/// returns the timed part as a closure. See tool/perf/README.md.
class BenchStepRunner {
  BenchStepRunner({required this.bench, required this.ref, required this.context});

  final PerfBench bench;
  final WidgetRef ref;
  final BuildContext context;

  StackRouter? get root => ref.read(routerProvider);

  String? get topRouteName => root?.topRoute.name;

  /// The router a person's tap would push onto: the stack of the tab on
  /// screen, or whatever is on top of it.
  StackRouter? get _topStack {
    final top = root?.topMostRouter();
    if (top is StackRouter) return top;
    return root;
  }

  BuildContext? get _topContext => _topStack?.navigatorKey.currentContext;

  String? Function()? _expectRoute(Map<String, dynamic> step) {
    final expected = step['expect_route'] as String?;
    if (expected == null) return null;
    return () {
      final current = topRouteName;
      return current == expected ? null : 'route $current (want $expected)';
    };
  }

  Future<PreparedStep> prepare(Map<String, dynamic> step) async {
    final action = step['action'] as String;
    switch (action) {
      case 'launch':
      case 'wait_ready':
        return PreparedStep(() async => Performed(condition: _expectRoute(step)));

      case 'sleep':
        return PreparedStep(() async {
          await Future<void>.delayed(Duration(milliseconds: (step['ms'] as num).toInt()));
          return Performed();
        });

      case 'login':
        return PreparedStep(() => _login(step));

      case 'open_item':
        // The item as a card holds it, fetched before the clock starts; the
        // timed part is the tap: `navigateTo`, prefetch included.
        final id = step['id'] as String;
        final response = await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: id);
        final item = response.body;
        if (item == null) return PreparedStep.failed('item $id not found (${response.statusCode})');
        return PreparedStep(() async {
          final context = _topContext;
          if (context == null) return Performed(error: 'no navigator');
          unawaited(item.navigateTo(context));
          return Performed(condition: _expectRoute(step));
        });

      case 'push':
        final route = _route(step);
        if (route == null) return PreparedStep.failed('unknown route ${step['route']}');
        return PreparedStep(() async {
          final stack = _topStack;
          if (stack == null) return Performed(error: 'no router');
          unawaited(stack.push(route));
          return Performed(condition: _expectRoute(step));
        });

      case 'tab':
        final tab = HomeTabs.values.byName(step['tab'] as String);
        return PreparedStep(() async {
          final router = root;
          if (router == null) return Performed(error: 'no router');
          showHomeTab(router, tab);
          return Performed(condition: _expectRoute(step));
        });

      case 'back':
        return PreparedStep(() async {
          unawaited(root?.maybePopTop());
          return Performed(condition: _expectRoute(step));
        });

      case 'type':
        return PreparedStep(() => _type(step));

      case 'scroll':
        return PreparedStep(() async {
          final scrollable = _largestScrollable();
          if (scrollable == null) return Performed(error: 'no scrollable');
          final position = scrollable.position;
          final to = step['to'];
          final target = to == 'end' || to == null ? position.maxScrollExtent : (to as num).toDouble();
          position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
          return Performed(
            condition: _expectRoute(step),
            extra: {'scroll_extent_before': position.maxScrollExtent},
          );
        });

      case 'tap':
        final type = step['widget'] as String?;
        final key = step['key'] as String?;
        final within = step['within'] as String?;
        final index = (step['index'] as num?)?.toInt() ?? 0;
        final what = [if (type != null) type, if (key != null) 'key $key', if (within != null) 'in $within'].join(' ');
        if (step['ensure_visible'] == true) {
          // Untimed: scroll the target into view and let the page settle, so
          // the timed part is only the tap and what it sets off.
          final element = _findWidgetElement(type, key: key, within: within, index: index);
          if (element == null) return PreparedStep.failed('no $what to scroll to');
          await Scrollable.ensureVisible(element, alignment: 0.5);
          await bench.detector(timeout: const Duration(seconds: 20)).waitUntilReady(Timeline.now);
        }
        return PreparedStep(() async {
          final box = _findWidgetBox(type, key: key, within: within, index: index);
          if (box == null) return Performed(error: 'no visible $what');
          final at = (step['at'] as List?)?.cast<num>();
          final point = at == null ? null : Offset(at[0].toDouble(), at[1].toDouble());
          if (step['ready'] == 'player') return _tapAndWaitForPlayer(box, step, at: point);
          _tap(box, at: point);
          return Performed(condition: _expectRoute(step));
        });

      case 'set_up_profile':
        return PreparedStep(() async {
          // Quiet and constant: no update checks against GitHub from dozens of
          // runs, and no sound from the play scenarios.
          ref.read(clientSettingsProvider.notifier).update((value) => value.copyWith(checkForUpdates: false));
          ref.read(videoPlayerSettingsProvider.notifier).setVolume(0);
          return Performed(condition: _expectRoute(step));
        });
    }
    return PreparedStep.failed('unknown action $action');
  }

  PageRouteInfo? _route(Map<String, dynamic> step) {
    final args = (step['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    return switch (step['route']) {
      'DetailsRoute' => DetailsRoute(id: args['id'] as String),
      'LibrarySearchRoute' => LibrarySearchRoute(
          parentId: (args['parentId'] as List?)?.cast<String>(),
          query: args['query'] as String?,
          recursive: args['recursive'] as bool?,
          types: (args['types'] as List?) == null
              ? null
              : {for (final type in (args['types'] as List).cast<String>()) FladderItemType.values.byName(type): true},
        ),
      _ => null,
    };
  }

  Future<Performed> _login(Map<String, dynamic> step) async {
    final login = bench.config.login;
    if (login == null) return Performed(error: 'no login in config');
    final auth = ref.read(authProvider.notifier);
    await auth.setServer(login['server'] as String);
    final response = await auth.authenticateByName(login['username'] as String, login['password'] as String? ?? '');
    if (response?.body == null) return Performed(error: 'login failed (${response?.statusCode})');
    ref.read(lockScreenActiveProvider.notifier).update((state) => false);
    unawaited(root?.replaceAll([const DashboardRoute()]));
    return Performed(condition: _expectRoute(step));
  }

  /// Types into the focused text field - or the first one on screen - the way
  /// the platform's text input does, a character at a time, then submits it.
  Future<Performed> _type(Map<String, dynamic> step) async {
    final field = _findEditable();
    if (field == null) return Performed(error: 'no text field');
    final text = step['text'] as String;
    final delay = Duration(milliseconds: (step['char_delay_ms'] as num?)?.toInt() ?? 90);
    final firstKeyUs = Timeline.now;
    var lastKeyUs = firstKeyUs;
    field.requestKeyboard();
    for (var i = 1; i <= text.length; i++) {
      final value = text.substring(0, i);
      lastKeyUs = Timeline.now;
      field.updateEditingValue(TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length)));
      if (i < text.length || step['submit'] != false) await Future<void>.delayed(delay);
    }
    if (step['submit'] == false) {
      // Nothing submitted (suggestions as you type): timed from the last key,
      // or the first with `measure_from: first_key`.
      return Performed(
        condition: _expectRoute(step),
        measureFromUs: step['measure_from'] == 'first_key' ? firstKeyUs : lastKeyUs,
        extra: {'typing_ms': (lastKeyUs - firstKeyUs) / 1000},
      );
    }
    final submitUs = Timeline.now;
    field.performAction(field.widget.textInputAction ?? TextInputAction.done);
    return Performed(
      condition: _expectRoute(step),
      measureFromUs: step['measure_from'] == 'first_key' ? firstKeyUs : submitUs,
      extra: {'typing_ms': (submitUs - firstKeyUs) / 1000},
    );
  }

  EditableTextState? _findEditable() {
    final focused = FocusManager.instance.primaryFocus?.context;
    EditableTextState? found;
    if (focused != null) {
      found = focused.findAncestorStateOfType<EditableTextState>();
      if (found == null && focused is Element) {
        void visit(Element e) {
          if (found != null) return;
          if (e is StatefulElement && e.state is EditableTextState) {
            found = e.state as EditableTextState;
            return;
          }
          e.visitChildren(visit);
        }

        visit(focused);
      }
    }
    return found ??
        (_findElements((e) => e is StatefulElement && e.state is EditableTextState).firstOrNull as StatefulElement?)
            ?.state as EditableTextState?;
  }

  ScrollableState? _largestScrollable() {
    ScrollableState? best;
    var bestArea = 0.0;
    for (final element in _findElements((e) => e is StatefulElement && e.state is ScrollableState)) {
      final state = (element as StatefulElement).state as ScrollableState;
      if (state.axisDirection != AxisDirection.down || !state.position.hasContentDimensions) continue;
      final box = element.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !_painted(box)) continue;
      final area = box.size.width * box.size.height;
      if (area > bestArea) {
        best = state;
        bestArea = area;
      }
    }
    return best;
  }

  /// The [index]th painted widget of type [typeName] and/or with a
  /// `ValueKey` of [key], optionally only inside widgets of type [within].
  Element? _findWidgetElement(String? typeName, {String? key, String? within, int index = 0}) {
    bool matches(Element e) =>
        (typeName == null || e.widget.runtimeType.toString() == typeName) &&
        (key == null || (e.widget.key is ValueKey && '${(e.widget.key as ValueKey).value}' == key));
    final candidates = within == null
        ? _findElements(matches)
        : [
            for (final outer in _findElements((e) => e.widget.runtimeType.toString() == within))
              ..._findElements(matches, root: outer),
          ];
    var seen = 0;
    for (final element in candidates) {
      final box = element.findRenderObject();
      if (box is! RenderBox || !box.hasSize || box.size.isEmpty || !_painted(box)) continue;
      if (seen++ == index) return element;
    }
    return null;
  }

  RenderBox? _findWidgetBox(String? typeName, {String? key, String? within, int index = 0}) =>
      _findWidgetElement(typeName, key: key, within: within, index: index)?.findRenderObject() as RenderBox?;

  static bool _painted(RenderObject object) {
    RenderObject child = object;
    var parent = child.parent;
    while (parent != null) {
      if (!parent.paintsChild(child)) return false;
      child = parent;
      parent = child.parent;
    }
    return object.attached;
  }

  List<Element> _findElements(bool Function(Element element) test, {Element? root}) {
    final found = <Element>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is TickerMode && !widget.enabled) return;
      // Hidden without being offstage: what IndexedStack does to the children
      // it is not showing. Its render object paints nothing but does not say so
      // through paintsChild.
      if (widget is Visibility && !widget.visible) return;
      if (widget is SliverVisibility && !widget.visible) return;
      if (test(element)) found.add(element);
      element.visitChildren(visit);
    }

    (root ?? WidgetsBinding.instance.rootElement)?.visitChildren(visit);
    return found;
  }

  /// A mouse click in the middle of [box] - or at [at], fractions of its width
  /// and height - dispatched to the app's own gesture system. The pointer is
  /// added and removed around it so it does not stay hovering over the page.
  void _tap(RenderBox box, {Offset? at}) {
    final local = at == null ? box.size.center(Offset.zero) : Offset(box.size.width * at.dx, box.size.height * at.dy);
    final center = box.localToGlobal(local);
    final viewId = WidgetsBinding.instance.platformDispatcher.views.first.viewId;
    const device = 9001;
    const pointer = 9001;
    final gestures = GestureBinding.instance;
    gestures.handlePointerEvent(PointerAddedEvent(viewId: viewId, device: device, position: center));
    gestures.handlePointerEvent(PointerHoverEvent(viewId: viewId, device: device, position: center));
    gestures.handlePointerEvent(PointerDownEvent(
      viewId: viewId,
      pointer: pointer,
      device: device,
      position: center,
      buttons: kPrimaryMouseButton,
    ));
    gestures.handlePointerEvent(PointerUpEvent(viewId: viewId, pointer: pointer, device: device, position: center));
    gestures.handlePointerEvent(PointerRemovedEvent(viewId: viewId, device: device, position: center));
  }

  /// Playback is ready when the player is playing and its position moves on
  /// at the pace of the clock: the first picture is up and running. Jumps -
  /// the seek to a resume point - do not count as moving.
  Future<Performed> _tapAndWaitForPlayer(RenderBox box, Map<String, dynamic> step, {Offset? at}) async {
    final player = ref.read(videoPlayerProvider);
    int? firstPlayingUs;
    int? readyUs;
    int? advancedUs;
    Duration? readyPosition;
    int? lastUs;
    Duration? lastPosition;
    var advanced = Duration.zero;
    final done = Completer<void>();
    final subscription = player.stateStream.listen((state) {
      final now = Timeline.now;
      if (!state.playing) {
        lastUs = null;
        return;
      }
      firstPlayingUs ??= now;
      final previousUs = lastUs;
      final previousPosition = lastPosition;
      lastUs = now;
      lastPosition = state.position;
      if (previousUs == null || previousPosition == null) return;
      final moved = state.position - previousPosition;
      final elapsed = Duration(microseconds: now - previousUs);
      if (moved <= Duration.zero || moved > elapsed * 2 + const Duration(milliseconds: 250)) return;
      readyUs ??= now;
      readyPosition ??= state.position;
      advanced += moved;
      if (advancedUs == null && advanced >= const Duration(seconds: 1)) {
        advancedUs = now;
        if (!done.isCompleted) done.complete();
      }
    });
    _tap(box, at: at);
    await done.future.timeout(bench.config.stepTimeout, onTimeout: () {});
    await subscription.cancel();
    final detectedUs = Timeline.now;
    if (step['stop'] != false) {
      await ref.read(videoPlayerProvider).stop();
    }
    return Performed(
      readyUs: readyUs,
      detectedUs: detectedUs,
      extra: {
        'first_playing_ms': firstPlayingUs,
        'advanced_1s_ms': advancedUs,
        'position_at_ready_s': readyPosition == null ? null : readyPosition!.inMilliseconds / 1000,
      },
    );
  }
}
