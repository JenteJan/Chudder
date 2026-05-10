import 'package:json_annotation/json_annotation.dart';
import 'package:collection/collection.dart';

enum MediaCategory {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  movie(0),
  @JsonValue(1)
  show(1),
  @JsonValue(2)
  anime(2),
  @JsonValue(3)
  none(3);

  final int? value;

  const MediaCategory(this.value);
}

enum CreationOrigin {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  discord(0),
  @JsonValue(1)
  jellyfin(1);

  final int? value;

  const CreationOrigin(this.value);
}

enum MediaServerType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  plex(0),
  @JsonValue(1)
  jellyfin(1);

  final int? value;

  const MediaServerType(this.value);
}

enum LiveTvChannelCategory {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  general(0),
  @JsonValue(1)
  sports(1),
  @JsonValue(2)
  cinema(2),
  @JsonValue(3)
  kids(3),
  @JsonValue(4)
  documentary(4),
  @JsonValue(5)
  music(5),
  @JsonValue(6)
  news(6),
  @JsonValue(7)
  other(7);

  final int? value;

  const LiveTvChannelCategory(this.value);
}

enum MediaQuality {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  unknown(0),
  @JsonValue(1)
  sd(1),
  @JsonValue(2)
  hd(2),
  @JsonValue(3)
  fullhd(3),
  @JsonValue(4)
  ultrahd(4);

  final int? value;

  const MediaQuality(this.value);
}

enum CrawlStatus {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue(0)
  scheduled(0),
  @JsonValue(1)
  crawling(1),
  @JsonValue(2)
  crawled(2),
  @JsonValue(3)
  downloading(3),
  @JsonValue(4)
  downloaded(4),
  @JsonValue(5)
  error(5),
  @JsonValue(6)
  cancelled(6),
  @JsonValue(50)
  crawlerreturnednolinks(50),
  @JsonValue(51)
  crawlerreturnedemptylinks(51),
  @JsonValue(52)
  deadlinks(52),
  @JsonValue(53)
  hostunavailable(53),
  @JsonValue(60)
  networkerror(60);

  final int? value;

  const CrawlStatus(this.value);
}
