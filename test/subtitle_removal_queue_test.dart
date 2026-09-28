import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/providers/subtitles/subtitle_file_actions.dart';

class _FakeActions implements SubtitleFileActions {
  final removed = <String?>[];

  @override
  Future<bool> remove(SubtitleRemoval removal, {bool block = false}) async {
    removed.add(removal.path);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SubtitleRemoval _plan(String path) =>
    SubtitleRemoval(itemId: 'movie', index: 3, path: path, jellyfinCanDelete: true);

void main() {
  late _FakeActions actions;
  late ProviderContainer container;

  setUp(() {
    actions = _FakeActions();
    container = ProviderContainer(overrides: [subtitleFileActionsProvider.overrideWith((ref) => actions)]);
  });
  tearDown(() => container.dispose());

  testWidgets('nothing is deleted inside the undo window', (tester) async {
    final queue = container.read(subtitleRemovalQueueProvider);
    queue.schedule(_plan('/m/a.en.srt'), block: false);
    await tester.pump(SubtitleRemovalQueue.undoWindow);
    expect(actions.removed, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(actions.removed, ['/m/a.en.srt']);
  });

  testWidgets('undo calls the removal off', (tester) async {
    final queue = container.read(subtitleRemovalQueueProvider);
    final pending = queue.schedule(_plan('/m/a.en.srt'), block: false);
    await tester.pump(const Duration(seconds: 5));
    expect(pending.undo(), isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(actions.removed, isEmpty);
    expect(await pending.result, isNull);
  });

  testWidgets('undo is refused once the delete has started', (tester) async {
    final queue = container.read(subtitleRemovalQueueProvider);
    final pending = queue.schedule(_plan('/m/a.en.srt'), block: false);
    await tester.pump(const Duration(seconds: 7));
    expect(pending.undo(), isFalse);
    expect(await pending.result, isTrue);
  });

  testWidgets('the same file asked twice is removed once', (tester) async {
    final queue = container.read(subtitleRemovalQueueProvider);
    final first = queue.schedule(_plan('/m/a.en.srt'), block: false);
    final second = queue.schedule(_plan('/m/a.en.srt'), block: false);
    expect(identical(first, second), isTrue);
    await tester.pump(const Duration(seconds: 7));
    expect(actions.removed, ['/m/a.en.srt']);
  });
}
