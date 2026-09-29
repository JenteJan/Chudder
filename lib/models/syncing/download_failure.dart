import 'package:background_downloader/background_downloader.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';

/// What went wrong with a download, in terms a person can act on.
enum DownloadFailureKind {
  /// The connection dropped or the server could not be reached. Retrying
  /// once back online usually does it.
  connection,

  /// The server answered, but not with the file: gone, refused, or an error
  /// while transcoding.
  server,

  /// The file could not be written: out of space, or the folder is gone.
  storage,

  /// Anything else.
  unknown;

  String label(AppLocalizations l10n) => switch (this) {
        DownloadFailureKind.connection => l10n.downloadFailedConnection,
        DownloadFailureKind.server => l10n.downloadFailedServer,
        DownloadFailureKind.storage => l10n.downloadFailedStorage,
        DownloadFailureKind.unknown => l10n.downloadFailedUnknown,
      };
}

/// The kind of failure and the downloader's own words for it, packed into
/// the one string a [DownloadStream] carries: `kind|detail`.
String describeDownloadFailure(TaskException? exception, int? statusCode) {
  final kind = switch (exception) {
    TaskConnectionException() => DownloadFailureKind.connection,
    TaskHttpException() => DownloadFailureKind.server,
    TaskUrlException() => DownloadFailureKind.server,
    TaskFileSystemException() => DownloadFailureKind.storage,
    TaskResumeException() => DownloadFailureKind.connection,
    _ when statusCode != null && statusCode >= 400 => DownloadFailureKind.server,
    _ => DownloadFailureKind.unknown,
  };
  final code = exception is TaskHttpException ? exception.httpResponseCode : statusCode;
  final detail = [
    if (code != null && code > 0) 'HTTP $code',
    if (exception?.description.isNotEmpty == true) exception!.description,
  ].join(' - ');
  return '${kind.name}|$detail';
}

/// Unpacks what [describeDownloadFailure] packed.
({DownloadFailureKind kind, String detail}) parseDownloadFailure(String? error) {
  if (error == null || error.isEmpty) return (kind: DownloadFailureKind.unknown, detail: '');
  final split = error.indexOf('|');
  if (split < 0) return (kind: DownloadFailureKind.unknown, detail: error);
  final kind = DownloadFailureKind.values.asNameMap()[error.substring(0, split)] ?? DownloadFailureKind.unknown;
  return (kind: kind, detail: error.substring(split + 1));
}
