/// Masks credentials in text that is about to be logged, stored or shared.
///
/// The crash log and cast log are files users attach to bug reports, and
/// their lines carry whatever a library put in an error message: dart:io's
/// WebSocket failure quotes the full socket URL, mpv quotes the stream URL,
/// a DLNA log quotes the subtitle URL. Every Jellyfin URL the app builds
/// for a player carries the account token, so each such line was the
/// account's key in plain text.
///
/// Covers the query parameters Jellyfin, Seerr and Bazarr accept
/// (`api_key`, `ApiKey`, `X-Emby-Token`, `accessToken`, `token`, `apikey`),
/// the `MediaBrowser … Token="…"` authorization header, `X-Api-Key` and
/// `Authorization: Bearer` style headers, and credentials embedded in a URL
/// (`https://user:password@host`).
String redactSecrets(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAllMapped(_queryParam, (m) => '${m[1]}${m[2]}=***')
      .replaceAllMapped(_tokenAttribute, (m) => '${m[1]}="***"')
      .replaceAllMapped(_header, (m) => '${m[1]}***')
      .replaceAllMapped(_userInfo, (m) => '${m[1]}***@');
}

final _queryParam = RegExp(
  r'([?&;]|\b)(api_key|apikey|x-emby-token|x-mediabrowser-token|access_?token|token|password|pw)=[^&\s"' "'" r'#]+',
  caseSensitive: false,
);

/// `Token="…"` inside a `MediaBrowser Client="…", …, Token="…"` header.
final _tokenAttribute = RegExp(r'\b(Token)="[^"]*"', caseSensitive: false);

final _header = RegExp(
  r'((?:x-api-key|x-emby-token|x-mediabrowser-token|authorization)\s*[:=]\s*(?:bearer\s+|basic\s+)?)[^\s,;"' "'" r']+',
  caseSensitive: false,
);

final _userInfo = RegExp(r'(\b[a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@', caseSensitive: false);
