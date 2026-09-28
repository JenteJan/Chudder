// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'bazarr_credentials_model.freezed.dart';
part 'bazarr_credentials_model.g.dart';

/// A Bazarr instance to ask for subtitles next to the server's own plugins.
/// Bazarr has one key for everything, so this is an admin's connection.
@Freezed(copyWith: true)
abstract class BazarrCredentialsModel with _$BazarrCredentialsModel {
  const BazarrCredentialsModel._();

  const factory BazarrCredentialsModel({
    @Default("") String serverUrl,
    @Default("") String apiKey,
  }) = _BazarrCredentialsModel;

  bool get isConfigured => serverUrl.isNotEmpty && apiKey.isNotEmpty;

  factory BazarrCredentialsModel.fromJson(Map<String, dynamic> json) => _$BazarrCredentialsModelFromJson(json);
}
