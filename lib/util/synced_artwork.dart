import 'package:path/path.dart' as p;

import 'package:chudder/models/items/images_models.dart';

/// The artwork downloads keep on disk, by the key the server's copy of the
/// same picture is cached under.
///
/// A download stores its own poster, thumb, logo and backdrops next to the
/// video, but the pictures an item shows are not always its own: an episode
/// card shows its show's poster, and anything reached through the server shows
/// the server's copy. Those went through the network cache, which evicts - so
/// offline, a downloaded episode could come up blank because its show's poster
/// had been pushed out. A key is an item, a kind and the picture's tag, so a
/// key found here is the very same picture, and it is drawn from the download.
class SyncedArtwork {
  SyncedArtwork._();

  static Map<String, String> _files = const {};

  /// Bumped on every change, so a picture that picked the network before the
  /// downloads were read picks again.
  static int generation = 0;

  static String? fileFor(String key) => _files[key];

  /// Replaces the index with every row's artwork: its folder, and the images
  /// as stored in the database, with paths relative to that folder.
  static void replaceAll(Iterable<({String? path, ImagesData? images})> rows) {
    final files = <String, String>{};
    for (final row in rows) {
      final folder = row.path;
      final images = row.images;
      if (folder == null || folder.isEmpty || images == null) continue;
      for (final image in [images.primary, images.thumb, images.logo, ...?images.backDrop]) {
        if (image == null || image.key.isEmpty || image.path.isEmpty || image.path.startsWith('http')) continue;
        files[image.key] = p.join(folder, image.path);
      }
    }
    if (_sameAs(files)) return;
    _files = files;
    generation++;
  }

  static bool _sameAs(Map<String, String> files) {
    if (files.length != _files.length) return false;
    for (final entry in files.entries) {
      if (_files[entry.key] != entry.value) return false;
    }
    return true;
  }
}
