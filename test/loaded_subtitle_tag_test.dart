import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

SubStreamModel _file(int index, String path) => SubStreamModel(
      name: '',
      id: 'sub$index',
      title: '',
      displayTitle: 'English - SUBRIP - External',
      language: 'eng',
      path: path,
      codec: 'subrip',
      isDefault: false,
      isExternal: true,
      index: index,
    );

void main() {
  test('a different file under the same number is not the loaded one', () {
    final before = loadedSubtitleTag(_file(0, '/m/film.en.srt'));
    final after = loadedSubtitleTag(_file(0, '/m/film.eng.0.srt'));
    expect(after, isNot(before));
    expect(after, startsWith(loadedSubtitlePrefix));
  });

  test('the same file rewritten in place is read again in a new generation', () {
    final file = _file(0, '/m/film.en.srt');
    expect(loadedSubtitleTag(file), loadedSubtitleTag(file));
    expect(loadedSubtitleTag(file, generation: 1), isNot(loadedSubtitleTag(file)));
  });
}
