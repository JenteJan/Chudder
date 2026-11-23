/// What is wrong with a typed server address, when it is something no server
/// could ever answer to. Everything a private server might use passes:
/// names without a dot, IPs, IPv6, ports, a path behind a reverse proxy,
/// letters outside ASCII, no scheme at all.
enum ServerAddressProblem {
  /// Spaces inside the address.
  spaces,

  /// A scheme other than http or https, or a mangled `://`.
  scheme,

  /// No host, a port out of range, or characters no host name has.
  malformed,
}

final _schemePrefix = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
// "https:/x", "https//x", "http:x": a scheme that lost part of its "://".
// A colon and digits is a host called http with a port, not a scheme.
final _mangledScheme = RegExp(r'^https?(:/?(?![/\d])|//)', caseSensitive: false);
// Letters and digits of any script, hyphens, dots and underscores - local
// names use all of them.
final _hostName = RegExp(r'^[\p{L}\p{N}\p{M}_-]+(\.[\p{L}\p{N}\p{M}_-]+)*\.?$', unicode: true);
final _ipv6 = RegExp(r'^[0-9a-fA-F:.]+(%[\w.-]+)?$');

/// Null when [input] could be a server; otherwise what is wrong with it.
ServerAddressProblem? checkServerAddress(String input) {
  final address = input.trim();
  if (address.isEmpty) return null;
  if (RegExp(r'\s').hasMatch(address)) return ServerAddressProblem.spaces;

  final hasScheme = _schemePrefix.hasMatch(address);
  if (hasScheme) {
    final scheme = address.substring(0, address.indexOf('://')).toLowerCase();
    if (scheme != 'http' && scheme != 'https') return ServerAddressProblem.scheme;
  } else if (_mangledScheme.hasMatch(address)) {
    return ServerAddressProblem.scheme;
  }

  final uri = Uri.tryParse(hasScheme ? address : 'https://$address');
  if (uri == null || uri.host.isEmpty) return ServerAddressProblem.malformed;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return ServerAddressProblem.malformed;

  // Uri lower-cases and percent-decodes the host; check what was typed.
  final authority = (hasScheme ? address.substring(address.indexOf('://') + 3) : address).split(RegExp(r'[/?#]')).first;
  final hostPart = authority.contains('@') ? authority.substring(authority.lastIndexOf('@') + 1) : authority;
  if (hostPart.startsWith('[')) {
    final end = hostPart.indexOf(']');
    if (end < 0 || !_ipv6.hasMatch(hostPart.substring(1, end))) return ServerAddressProblem.malformed;
    return null;
  }
  final host = hostPart.contains(':') ? hostPart.substring(0, hostPart.lastIndexOf(':')) : hostPart;
  if (!_hostName.hasMatch(host)) return ServerAddressProblem.malformed;
  return null;
}
