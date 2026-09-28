// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bazarr_credentials_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BazarrCredentialsModel _$BazarrCredentialsModelFromJson(
        Map<String, dynamic> json) =>
    _BazarrCredentialsModel(
      serverUrl: json['serverUrl'] as String? ?? "",
      apiKey: json['apiKey'] as String? ?? "",
    );

Map<String, dynamic> _$BazarrCredentialsModelToJson(
        _BazarrCredentialsModel instance) =>
    <String, dynamic>{
      'serverUrl': instance.serverUrl,
      'apiKey': instance.apiKey,
    };
