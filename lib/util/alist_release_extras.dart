class AlistReleaseExtras {
  final DateTime? publishedAt;
  final Map<String, String> sha256;
  final String? minSupported;

  const AlistReleaseExtras({
    this.publishedAt,
    this.sha256 = const {},
    this.minSupported,
  });
}
