// What the Downloads tab says about a download: why it failed, and which
// quality it was asked for in.

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/syncing/download_failure.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/models/syncing/transcode_download_model.dart';
import 'package:chudder/util/bitrate_helper.dart';

void main() {
  group('failure reasons', () {
    test('a server error is the server, with its code', () {
      final packed = describeDownloadFailure(TaskHttpException('Internal Server Error', 500), 500);
      final parsed = parseDownloadFailure(packed);
      expect(parsed.kind, DownloadFailureKind.server);
      expect(parsed.detail, contains('HTTP 500'));
    });

    test('a dropped connection is the connection', () {
      final parsed = parseDownloadFailure(describeDownloadFailure(TaskConnectionException('reset'), null));
      expect(parsed.kind, DownloadFailureKind.connection);
    });

    test('a write that failed is storage', () {
      final parsed = parseDownloadFailure(describeDownloadFailure(TaskFileSystemException('No space'), null));
      expect(parsed.kind, DownloadFailureKind.storage);
    });

    test('nothing to go on reads as unknown rather than throwing', () {
      expect(parseDownloadFailure(null).kind, DownloadFailureKind.unknown);
      expect(parseDownloadFailure('garbage').kind, DownloadFailureKind.unknown);
    });
  });

  group('download state', () {
    test('paused and retrying still count as on their way', () {
      for (final status in [TaskStatus.enqueued, TaskStatus.running, TaskStatus.paused, TaskStatus.waitingToRetry]) {
        expect(DownloadStream(id: 'x', status: status).isPending, isTrue, reason: '$status');
      }
      expect(DownloadStream(id: 'x', status: TaskStatus.failed).isPending, isFalse);
    });

    test('clearing the error on a copy clears it', () {
      final failed = DownloadStream(id: 'x', status: TaskStatus.failed, error: 'server|HTTP 500');
      expect(failed.copyWith(status: TaskStatus.running, error: () => null).error, isNull);
      expect(failed.copyWith(status: TaskStatus.failed).error, 'server|HTTP 500');
    });
  });

  group('quality presets', () {
    test('each preset is recognised from its own settings', () {
      for (final preset in [DownloadQualityPreset.high, DownloadQualityPreset.balanced, DownloadQualityPreset.small]) {
        expect(DownloadQualityPreset.of(preset.model!), preset);
      }
      expect(DownloadQualityPreset.of(TranscodeDownloadModel.fromDefaults()), DownloadQualityPreset.original);
    });

    test('settings no preset has are custom', () {
      final odd = DownloadQualityPreset.balanced.model!.copyWith(maxBitrate: Bitrate.b20Mbps);
      expect(DownloadQualityPreset.of(odd), DownloadQualityPreset.custom);
    });

    test('the resolution is asked of the server, not only written down', () {
      final profile = DownloadQualityPreset.small.model!.deviceProfile;
      final condition = profile.codecProfiles!.single.conditions!.single;
      expect(condition.$Value, '480');
    });

    test('a two hour film at 4 Mbps comes to about 4 GB', () {
      final bytes = estimateDownloadBytes(const Duration(hours: 2), 4000000);
      expect(bytes, closeTo(3.96e9, 0.05e9));
    });
  });
}
