/// Which tracks go when downloaded music is removed.
///
/// A track is one row under its album and artist, however it came down, and a
/// playlist owns nothing: it only lists track ids. So a track can be needed by
/// its album, by its artist and by any number of playlists at once, and
/// removing one of them must not quietly take the track from the others.
///
/// No I/O in here: the caller reads what the database and the playlists say,
/// this decides.
library;

/// What the person chose to happen to the tracks.
enum MusicRemovalMode {
  /// Every track under the item goes.
  everything,

  /// Tracks something else still uses stay.
  keepShared,

  /// Every track stays; only the item itself goes (a playlist).
  keepAll,
}

/// Whether the item removed is a playlist or an album / artist.
enum MusicRemovalScope { playlist, library }

class MusicRemovalPlan {
  const MusicRemovalPlan({required this.remove, required this.keep, required this.affectedPlaylists});

  /// Tracks to delete.
  final Set<String> remove;

  /// Tracks that stay.
  final Set<String> keep;

  /// Playlists (other than the one being removed) that list any of the tracks
  /// under the item, so the person can be told who is affected.
  final Set<String> affectedPlaylists;
}

/// Decides what happens to [tracks], every track under the item removed.
///
/// [playlists] maps every downloaded playlist to the track ids it lists.
/// [removedPlaylistId] is the playlist itself when one is being removed.
///
/// A playlist's tracks have no way of saying whether the album they sit in
/// was downloaded on purpose. A track is taken to be wanted by its album when
/// that album holds a track the playlist does not list: whoever got the album
/// down got more than the playlist asked for. That errs towards keeping.
/// [tracksOfAlbum] is what each album row holds, and [albumOf] which album a
/// track sits in.
MusicRemovalPlan planMusicRemoval({
  required MusicRemovalScope scope,
  required MusicRemovalMode mode,
  required Set<String> tracks,
  required Map<String, Set<String>> playlists,
  String? removedPlaylistId,
  Map<String, String?> albumOf = const {},
  Map<String, Set<String>> tracksOfAlbum = const {},
}) {
  final others = {
    for (final entry in playlists.entries)
      if (entry.key != removedPlaylistId) entry.key: entry.value,
  };
  final affected = {
    for (final entry in others.entries)
      if (entry.value.any(tracks.contains)) entry.key,
  };

  switch (mode) {
    case MusicRemovalMode.keepAll:
      return MusicRemovalPlan(remove: const {}, keep: {...tracks}, affectedPlaylists: affected);
    case MusicRemovalMode.everything:
      return MusicRemovalPlan(remove: {...tracks}, keep: const {}, affectedPlaylists: affected);
    case MusicRemovalMode.keepShared:
      final keep = <String>{};
      for (final track in tracks) {
        final inAnotherPlaylist = others.values.any((listed) => listed.contains(track));
        var inItsAlbum = false;
        if (scope == MusicRemovalScope.playlist) {
          final album = albumOf[track];
          inItsAlbum = album != null && (tracksOfAlbum[album] ?? const <String>{}).any((other) => !tracks.contains(other));
        }
        if (inAnotherPlaylist || inItsAlbum) keep.add(track);
      }
      return MusicRemovalPlan(remove: tracks.difference(keep), keep: keep, affectedPlaylists: affected);
  }
}
