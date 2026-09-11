// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_info_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SessionInfoModel _$SessionInfoModelFromJson(Map<String, dynamic> json) =>
    _SessionInfoModel(
      playbackModel: json['playbackModel'] as String?,
      transCodeInfo: json['transCodeInfo'] == null
          ? null
          : TranscodingInfo.fromJson(
              json['transCodeInfo'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SessionInfoModelToJson(_SessionInfoModel instance) =>
    <String, dynamic>{
      'playbackModel': instance.playbackModel,
      'transCodeInfo': instance.transCodeInfo,
    };

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sessionInfoHash() => r'51e14304fe35e96af3c7d3a66e142c481ffcf941';

/// See also [SessionInfo].
@ProviderFor(SessionInfo)
final sessionInfoProvider =
    AutoDisposeNotifierProvider<SessionInfo, SessionInfoModel>.internal(
  SessionInfo.new,
  name: r'sessionInfoProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$sessionInfoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SessionInfo = AutoDisposeNotifier<SessionInfoModel>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
