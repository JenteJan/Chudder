import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/util/fuzzy_match.dart';

void main() {
  test('a substring is the server\'s job and scores highest', () {
    expect(fuzzyScore("Inglourious Basterds", "basterds"), 1);
  });

  test('a misspelling the server would miss still matches', () {
    expect(fuzzyScore("Inglourious Basterds", "inglorious"), greaterThan(0));
    expect(fuzzyScore("The Shawshank Redemption", "shawshenk"), greaterThan(0));
    expect(fuzzyScore("Interstellar", "intersteller"), greaterThan(0));
  });

  test('a transposition is one mistake, not two', () {
    expect(fuzzyScore("The Matrix", "teh matrix"), greaterThan(0));
  });

  test('a different film is not a near miss', () {
    expect(fuzzyScore("Interstellar", "gladiator"), 0);
    expect(fuzzyScore("The Godfather", "goodfellas"), 0);
    expect(fuzzyScore("Alien", "aliens vs predator"), 0);
  });

  test('one word of a long title can carry the match on its own', () {
    expect(fuzzyScore("Alien: Resurrection", "resurection"), greaterThan(0));
  });

  test('a query too short to be a typo is left to the server', () {
    expect(fuzzyScore("Interstellar", "in"), 0);
    expect(fuzzyScore("Interstellar", "j"), 0);
  });

  test('scoring is stable whichever way round the strings are', () {
    expect(fuzzyScore("Se7en", ""), 0);
    expect(fuzzyScore("", "anything"), 0);
  });
}
