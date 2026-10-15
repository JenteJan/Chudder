import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/settings/key_combinations.dart';
import 'package:chudder/util/input_handler.dart';

enum _Key { space, earlier }

/// A player-like page: its own keys at the top, raw ones beside them, and a
/// panel over it that keeps the keys while it is open.
class _Page extends StatelessWidget {
  const _Page({required this.panelOpen, required this.onPlayer, required this.onRaw, required this.onPanel});

  final bool panelOpen;
  final ValueChanged<_Key> onPlayer;
  final ValueChanged<_Key> onRaw;
  final ValueChanged<_Key> onPanel;

  static final _space = KeyCombination(key: LogicalKeyboardKey.space);
  static final _earlier = KeyCombination(key: LogicalKeyboardKey.keyZ);

  @override
  Widget build(BuildContext context) {
    return InputHandler<_Key>(
      keyMap: {_Key.space: _space, _Key.earlier: _earlier},
      keyMapResult: (key) {
        onPlayer(key);
        return true;
      },
      child: Column(
        children: [
          InputHandler<_Key>(
            autoFocus: false,
            listenRawKeyboard: true,
            keyMap: {_Key.space: _space},
            keyMapResult: (key) {
              onRaw(key);
              return false;
            },
            child: const SizedBox(height: 10),
          ),
          if (panelOpen)
            KeyGuard(
              active: true,
              child: InputHandler<_Key>(
                autoFocus: false,
                keyMap: {_Key.earlier: _earlier},
                keyMapResult: (key) {
                  onPanel(key);
                  return true;
                },
                child: TextButton(autofocus: true, onPressed: () {}, child: const Text('Step')),
              ),
            ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('an open panel keeps the keys, and gives them back when it closes', (tester) async {
    final player = <_Key>[];
    final raw = <_Key>[];
    final panel = <_Key>[];

    Future<void> pump(bool open) => tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: _Page(panelOpen: open, onPlayer: player.add, onRaw: raw.add, onPanel: panel.add),
            ),
          ),
        ));

    await pump(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(player, [_Key.space]);
    expect(raw, [_Key.space]);

    player.clear();
    raw.clear();
    await pump(true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    // Space presses the focused button now, not the player's play/pause.
    expect(player, isEmpty);
    expect(raw, isEmpty);
    expect(panel, [_Key.earlier]);

    await pump(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(player, [_Key.space]);
  });
}
