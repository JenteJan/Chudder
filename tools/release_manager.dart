// Maktep release manager: builds Android + Windows artifacts, uploads to
// AList over WebDAV, and updates manifest.json.

import 'dart:io';

class PubspecVersion {
  final String version;
  final int buildNumber;
  const PubspecVersion(this.version, this.buildNumber);
}

final _versionLine = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', multiLine: true);

PubspecVersion parsePubspecVersion(String yamlText) {
  final m = _versionLine.firstMatch(yamlText);
  if (m == null) {
    throw const FormatException(
      "could not find a 'version: X.Y.Z+N' line in pubspec.yaml",
    );
  }
  return PubspecVersion(m.group(1)!, int.parse(m.group(2)!));
}

String bumpPubspecVersion(String yamlText, String level) {
  final current = parsePubspecVersion(yamlText);
  final parts = current.version.split('.').map(int.parse).toList();
  var build = current.buildNumber;

  switch (level) {
    case 'major':
      parts[0]++;
      parts[1] = 0;
      parts[2] = 0;
    case 'minor':
      parts[1]++;
      parts[2] = 0;
    case 'patch':
      parts[2]++;
    case 'build':
      build++;
    default:
      throw ArgumentError.value(level, 'level',
          'must be one of: major, minor, patch, build');
  }

  final newVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
  return yamlText.replaceFirst(_versionLine, 'version: $newVersion+$build');
}

void main(List<String> args) {
  stderr.writeln('release_manager: not yet implemented');
  exit(64);
}
