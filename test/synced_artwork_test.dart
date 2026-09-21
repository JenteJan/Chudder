import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/util/synced_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The network provider builds the cache manager, which asks for a folder.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  const showKey = 'show_primary_tag1';
  final folder = p.join('downloads', 'show');

  ImageData network(String key) => ImageData(path: 'https://server/Items/x/Images/Primary?tag=1', key: key);

  tearDown(() => SyncedArtwork.replaceAll(const []));

  test('a picture a download keeps is drawn from its file', () {
    SyncedArtwork.replaceAll([
      (path: folder, images: ImagesData(primary: ImageData(path: 'primary.jpg', key: showKey))),
    ]);

    final provider = network(showKey).imageProvider;
    expect(provider, isA<FileImage>());
    expect((provider as FileImage).file.path, p.join(folder, 'primary.jpg'));
  });

  test('another tag of the same picture still comes from the server', () {
    SyncedArtwork.replaceAll([
      (path: folder, images: ImagesData(primary: ImageData(path: 'primary.jpg', key: showKey))),
    ]);

    expect(network('show_primary_tag2').imageProvider, isA<CachedNetworkImageProvider>());
  });

  test('server URLs a download still holds are not taken for files', () {
    SyncedArtwork.replaceAll([
      (path: folder, images: ImagesData(thumb: ImageData(path: 'https://server/thumb', key: 'show_thumb_t'))),
    ]);

    expect(SyncedArtwork.fileFor('show_thumb_t'), isNull);
  });

  test('a picture asked for before the downloads were read picks again', () {
    final image = network(showKey);
    expect(image.imageProvider, isA<CachedNetworkImageProvider>());

    SyncedArtwork.replaceAll([
      (path: folder, images: ImagesData(primary: ImageData(path: 'primary.jpg', key: showKey))),
    ]);

    expect(image.imageProvider, isA<FileImage>());
  });
}
