import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart' as enums;
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/providers/api_provider.dart';

/// Runs [build] with a [Ref], the way the models map items.
T withRef<T>(T Function(Ref ref) build) {
  final container = ProviderContainer(
    overrides: [serverUrlProvider.overrideWith((ref) => 'https://server.invalid')],
  );
  addTearDown(container.dispose);
  return container.read(Provider<T>((ref) => build(ref)));
}

Map<String, String> query(String url) => Uri.parse(url).queryParameters;

void main() {
  group('ArtworkSizes.forScreen', () {
    test('a poster is as wide as the detail poster needs at this pixel ratio', () {
      ArtworkSizes at(double ratio) =>
          ArtworkSizes.forScreen(devicePixelRatio: ratio, longestScreenSide: 2560, leanBack: false);
      expect(at(1).posterFill, 400);
      expect(at(1.25).posterFill, 400);
      expect(at(1.5).posterFill, 500);
      expect(at(2).posterFill, 600);
      expect(at(3.5).posterFill, 600);
    });

    test('backdrops are 16:9 and never wider than the screen needs', () {
      final hd = ArtworkSizes.forScreen(devicePixelRatio: 1, longestScreenSide: 1920, leanBack: false);
      final qhd = ArtworkSizes.forScreen(devicePixelRatio: 1.25, longestScreenSide: 2560, leanBack: false);
      final uhd = ArtworkSizes.forScreen(devicePixelRatio: 1.5, longestScreenSide: 3840, leanBack: false);
      expect(hd.backdrop, const Size(1920, 1080));
      expect(qhd.backdrop, const Size(1920, 1080));
      expect(uhd.backdrop, const Size(3840, 2160));
    });

    test('a television asks for the smallest, it decodes everything to 520 tall', () {
      final tv = ArtworkSizes.forScreen(devicePixelRatio: 2, longestScreenSide: 3840, leanBack: true);
      expect(tv.posterFill, 400);
      expect(tv.backdrop, const Size(1920, 1080));
    });

    test('a logo is bounded by the widest header at this pixel ratio, 700 logical pixels', () {
      for (final ratio in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        final sizes = ArtworkSizes.forScreen(devicePixelRatio: ratio, longestScreenSide: 2560, leanBack: false);
        expect(sizes.logo.width, greaterThanOrEqualTo((700 * ratio).clamp(0, 1500)));
        expect(sizes.logo.width, lessThanOrEqualTo(1500));
      }
    });
  });

  group('ImagesData URLs', () {
    const tags = {'Primary': 'p1', 'Logo': 'l1', 'Thumb': 't1'};

    test('a film asks for a poster box, a backdrop box and a bounded WebP logo', () {
      final images = withRef((ref) => ImagesData.fromBaseItem(
            const dto.BaseItemDto(
              id: 'movie',
              type: enums.BaseItemKind.movie,
              imageTags: tags,
              backdropImageTags: ['b1'],
            ),
            ref,
          ))!;
      final sizes = withRef(ArtworkSizes.of);

      final primary = query(images.primary!.path);
      expect(primary['fillWidth'], '${sizes.posterFill}');
      expect(primary['fillHeight'], '${sizes.posterFill}');
      expect(primary['tag'], 'p1');
      // The key is what a row and the page it opens share; it has no size in it.
      expect(images.primary!.key, 'movie_primary_p1');

      final backdrop = query(images.backDrop!.single.path);
      expect(int.parse(backdrop['fillWidth']!) * 9, int.parse(backdrop['fillHeight']!) * 16);

      final logo = query(images.logo!.path);
      expect(logo['maxWidth'], '${(sizes.logo.width).toInt()}');
      expect(logo['maxHeight'], '${(sizes.logo.height).toInt()}');
      expect(logo['format'], 'Webp');
      expect(logo.containsKey('fillWidth'), isFalse);
    });

    test('an episode still keeps the old primary box', () {
      final images = withRef((ref) => ImagesData.fromBaseItem(
            const dto.BaseItemDto(id: 'episode', type: enums.BaseItemKind.episode, imageTags: tags),
            ref,
          ))!;
      expect(query(images.primary!.path)['fillWidth'], '600');
    });

    test("a library's tile asks for no more than the tile needs, whatever its shape", () {
      final images = withRef((ref) => ImagesData.fromBaseItem(
            const dto.BaseItemDto(id: 'library', type: enums.BaseItemKind.collectionfolder, imageTags: tags),
            ref,
          ))!;
      final primary = query(images.primary!.path);
      expect(primary['fillWidth'], primary['fillHeight']);
      expect(int.parse(primary['fillWidth']!), lessThanOrEqualTo(600));
    });

    test("an episode's show poster is the same URL as the show's own", () {
      final show = withRef((ref) => ImagesData.fromBaseItem(
            const dto.BaseItemDto(id: 'show', type: enums.BaseItemKind.series, imageTags: {'Primary': 'sp', 'Logo': 'sl'}),
            ref,
          ))!;
      final parent = withRef((ref) => ImagesData.fromBaseItemParent(
            const dto.BaseItemDto(
              id: 'episode',
              type: enums.BaseItemKind.episode,
              seriesId: 'show',
              seriesPrimaryImageTag: 'sp',
              parentLogoItemId: 'show',
              parentLogoImageTag: 'sl',
            ),
            ref,
          ))!;
      expect(parent.primary!.key, show.primary!.key);
      expect(parent.primary!.path, show.primary!.path);
      expect(parent.logo!.key, show.logo!.key);
      expect(parent.logo!.path, show.logo!.path);
    });

    test("a cast member's avatar is the same URL as the person's own page", () {
      final page = withRef((ref) => ImagesData.fromBaseItem(
            const dto.BaseItemDto(id: 'person', type: enums.BaseItemKind.person, imageTags: {'Primary': 'pp'}),
            ref,
          ))!;
      final avatar = withRef((ref) => ImagesData.fromPersonDto(
            const dto.BaseItemPerson(
              id: 'person',
              primaryImageTag: 'pp',
              imageBlurHashes: dto.BaseItemPerson$ImageBlurHashes(),
            ),
            ref,
          ))!;
      expect(avatar.primary!.key, page.primary!.key);
      expect(avatar.primary!.path, page.primary!.path);
    });
  });
}
