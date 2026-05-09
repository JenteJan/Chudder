import 'dart:async';
import 'dart:io';

import 'package:fladder/providers/update_downloader_provider.dart';
import 'package:fladder/util/alist_download_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAlistDownloadClient implements AlistDownloadClient {
  final StreamController<AlistDownloadEvent> _controller =
      StreamController<AlistDownloadEvent>.broadcast();
  String? lastTaskId;
  String? lastUrl;
  bool cancelled = false;

  @override
  Stream<AlistDownloadEvent> download({
    required String taskId,
    required String url,
    required String filename,
  }) {
    lastTaskId = taskId;
    lastUrl = url;
    return _controller.stream;
  }

  @override
  Future<void> cancel(String taskId) async {
    cancelled = true;
    _controller.add(AlistDownloadEvent.cancelled());
  }

  void emitProgress(double p) => _controller.add(AlistDownloadEvent.progress(p));
  void emitComplete(String path) =>
      _controller.add(AlistDownloadEvent.complete(path));
  void emitFailure(String reason) =>
      _controller.add(AlistDownloadEvent.failed(reason));
}

class _CapturingInstaller {
  String? installedPath;
  bool succeed = true;
  Future<bool> call(String path) async {
    installedPath = path;
    return succeed;
  }
}

void main() {
  late FakeAlistDownloadClient fakeClient;
  late _CapturingInstaller installer;
  late ProviderContainer container;

  setUp(() {
    fakeClient = FakeAlistDownloadClient();
    installer = _CapturingInstaller();
    container = ProviderContainer(overrides: [
      alistDownloadClientProvider.overrideWithValue(fakeClient),
      alistInstallerProvider.overrideWithValue(installer.call),
    ]);
  });

  tearDown(() {
    container.dispose();
  });

  test('initial state is idle', () {
    final state = container.read(updateDownloaderProvider);
    expect(state.kind, UpdateDownloadStateKind.idle);
  });

  test('start emits progress then completes to ready (no sha256)', () async {
    final notifier = container.read(updateDownloaderProvider.notifier);
    await notifier.start(
      version: '0.10.4',
      url: 'https://x/y.apk',
      filename: 'Fladder-Android.apk',
      expectedSha256: null,
    );

    fakeClient.emitProgress(0.5);
    await Future.delayed(Duration.zero);
    expect(container.read(updateDownloaderProvider).kind,
        UpdateDownloadStateKind.downloading);
    expect(container.read(updateDownloaderProvider).progress, 0.5);

    final tmp = await Directory.systemTemp.createTemp('alist-dl-');
    final f = File('${tmp.path}/Fladder-Android.apk')..writeAsStringSync('apk');
    fakeClient.emitComplete(f.path);
    await Future.delayed(Duration.zero);

    expect(container.read(updateDownloaderProvider).kind,
        UpdateDownloadStateKind.ready);
    expect(container.read(updateDownloaderProvider).filePath, f.path);

    await tmp.delete(recursive: true);
  });

  test('failure transitions to failed(network)', () async {
    final notifier = container.read(updateDownloaderProvider.notifier);
    await notifier.start(
      version: '0.10.4',
      url: 'https://x/y.apk',
      filename: 'Fladder-Android.apk',
      expectedSha256: null,
    );

    fakeClient.emitFailure('boom');
    await Future.delayed(Duration.zero);

    final state = container.read(updateDownloaderProvider);
    expect(state.kind, UpdateDownloadStateKind.failed);
    expect(state.failure, DownloadFailure.network);
  });

  test('cancel emits cancelled event and returns to idle', () async {
    final notifier = container.read(updateDownloaderProvider.notifier);
    await notifier.start(
      version: '0.10.4',
      url: 'https://x/y.apk',
      filename: 'Fladder-Android.apk',
      expectedSha256: null,
    );

    fakeClient.emitProgress(0.3);
    await Future.delayed(Duration.zero);

    await notifier.cancel();
    await Future.delayed(Duration.zero);

    expect(fakeClient.cancelled, isTrue);
    expect(container.read(updateDownloaderProvider).kind,
        UpdateDownloadStateKind.idle);
  });

  test('install transitions ready -> installing -> done on success', () async {
    final notifier = container.read(updateDownloaderProvider.notifier);
    await notifier.start(
      version: '0.10.4',
      url: 'https://x/y.apk',
      filename: 'Fladder-Android.apk',
      expectedSha256: null,
    );

    final tmp = await Directory.systemTemp.createTemp('alist-dl-');
    final f = File('${tmp.path}/Fladder-Android.apk')..writeAsStringSync('apk');
    fakeClient.emitComplete(f.path);
    await Future.delayed(Duration.zero);

    await notifier.install();
    expect(installer.installedPath, f.path);
    expect(container.read(updateDownloaderProvider).kind,
        UpdateDownloadStateKind.done);

    await tmp.delete(recursive: true);
  });

  test('install transitions to failed(installRefused) on installer false', () async {
    installer.succeed = false;
    final notifier = container.read(updateDownloaderProvider.notifier);
    await notifier.start(
      version: '0.10.4',
      url: 'https://x/y.apk',
      filename: 'Fladder-Android.apk',
      expectedSha256: null,
    );

    final tmp = await Directory.systemTemp.createTemp('alist-dl-');
    final f = File('${tmp.path}/Fladder-Android.apk')..writeAsStringSync('apk');
    fakeClient.emitComplete(f.path);
    await Future.delayed(Duration.zero);

    await notifier.install();
    final state = container.read(updateDownloaderProvider);
    expect(state.kind, UpdateDownloadStateKind.failed);
    expect(state.failure, DownloadFailure.installRefused);

    await tmp.delete(recursive: true);
  });

  test('start wipes <cache>/updates/ before downloading', () async {
    // Cannot exercise path_provider in unit tests without MethodChannel mocks.
  }, skip: 'manual: requires real path_provider');
}
