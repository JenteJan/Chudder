// Subtitle file names are the video's own name with a few letters on the
// end - `Malignant (2021) Bluray-1080p Proper [x265].eng.0.srt` - so the
// part that tells two of them apart is the part a narrow line cuts off.

/// [name] shortened in the middle, keeping its ending.
String shortSubtitleName(String name, {int max = 42}) {
  if (name.length <= max) return name;
  const keepEnd = 22;
  return '${name.substring(0, max - keepEnd - 1).trimRight()}…${name.substring(name.length - keepEnd)}';
}

/// For each of [names], what is left after the start they all share - `eng.srt`
/// against `en.srt` - or the name itself when there is only one, or nothing
/// is shared.
List<String> distinctSubtitleSuffixes(List<String> names) {
  final files = names.where((n) => n.isNotEmpty).toList();
  if (files.length < 2) return names;
  var prefix = files.first;
  for (final name in files.skip(1)) {
    var i = 0;
    while (i < prefix.length && i < name.length && prefix[i] == name[i]) {
      i++;
    }
    prefix = prefix.substring(0, i);
  }
  // Cut at a dot, so "…[x265].eng.srt" and "…[x265].en.srt" become "eng.srt"
  // and "en.srt", not "g.srt" and ".srt".
  final dot = prefix.lastIndexOf('.');
  final cut = dot == -1 ? 0 : dot + 1;
  if (cut < 8) return names;
  return [for (final name in names) name.length > cut ? name.substring(cut) : name];
}
