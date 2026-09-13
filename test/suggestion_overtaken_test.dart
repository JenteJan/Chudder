// A suggestion search overtaken by more typing lets the field move on at once
// instead of holding the search for the new text back until it has answered.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/screens/library_search/widgets/suggestion_search_bar.dart';

void main() {
  test('the answer, when the text is still what was searched for', () async {
    final field = TextEditingController(text: 'the');
    final search = Completer<List<String>>();
    final result = unlessOvertaken(field, 'the', search.future, showing: () => ['old']);
    search.complete(['The General']);
    expect(await result, ['The General']);
  });

  test('what is showing, as soon as the text moves on', () async {
    final field = TextEditingController(text: 'th');
    final search = Completer<List<String>>();
    var done = false;
    final result = unlessOvertaken(field, 'th', search.future, showing: () => ['old']).whenComplete(() => done = true);
    await pumpEventQueue();
    expect(done, isFalse);

    field.text = 'the';
    expect(await result, ['old'], reason: 'not waiting for the search for "th" to answer');
    search.complete(['late']);
  });

  test('what is showing, for a search whose text had already gone', () async {
    final field = TextEditingController(text: 'the');
    expect(await unlessOvertaken(field, 'th', Completer<List<String>>().future, showing: () => ['old']), ['old']);
  });
}
