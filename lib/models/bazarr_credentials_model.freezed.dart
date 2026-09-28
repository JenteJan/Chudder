// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bazarr_credentials_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BazarrCredentialsModel {
  String get serverUrl;
  String get apiKey;

  /// Create a copy of BazarrCredentialsModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $BazarrCredentialsModelCopyWith<BazarrCredentialsModel> get copyWith =>
      _$BazarrCredentialsModelCopyWithImpl<BazarrCredentialsModel>(
          this as BazarrCredentialsModel, _$identity);

  /// Serializes this BazarrCredentialsModel to a JSON map.
  Map<String, dynamic> toJson();

  @override
  String toString() {
    return 'BazarrCredentialsModel(serverUrl: $serverUrl, apiKey: $apiKey)';
  }
}

/// @nodoc
abstract mixin class $BazarrCredentialsModelCopyWith<$Res> {
  factory $BazarrCredentialsModelCopyWith(BazarrCredentialsModel value,
          $Res Function(BazarrCredentialsModel) _then) =
      _$BazarrCredentialsModelCopyWithImpl;
  @useResult
  $Res call({String serverUrl, String apiKey});
}

/// @nodoc
class _$BazarrCredentialsModelCopyWithImpl<$Res>
    implements $BazarrCredentialsModelCopyWith<$Res> {
  _$BazarrCredentialsModelCopyWithImpl(this._self, this._then);

  final BazarrCredentialsModel _self;
  final $Res Function(BazarrCredentialsModel) _then;

  /// Create a copy of BazarrCredentialsModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? serverUrl = null,
    Object? apiKey = null,
  }) {
    return _then(_self.copyWith(
      serverUrl: null == serverUrl
          ? _self.serverUrl
          : serverUrl // ignore: cast_nullable_to_non_nullable
              as String,
      apiKey: null == apiKey
          ? _self.apiKey
          : apiKey // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [BazarrCredentialsModel].
extension BazarrCredentialsModelPatterns on BazarrCredentialsModel {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_BazarrCredentialsModel value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_BazarrCredentialsModel value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_BazarrCredentialsModel value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(String serverUrl, String apiKey)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel() when $default != null:
        return $default(_that.serverUrl, _that.apiKey);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(String serverUrl, String apiKey) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel():
        return $default(_that.serverUrl, _that.apiKey);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(String serverUrl, String apiKey)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BazarrCredentialsModel() when $default != null:
        return $default(_that.serverUrl, _that.apiKey);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _BazarrCredentialsModel extends BazarrCredentialsModel {
  const _BazarrCredentialsModel({this.serverUrl = "", this.apiKey = ""})
      : super._();
  factory _BazarrCredentialsModel.fromJson(Map<String, dynamic> json) =>
      _$BazarrCredentialsModelFromJson(json);

  @override
  @JsonKey()
  final String serverUrl;
  @override
  @JsonKey()
  final String apiKey;

  /// Create a copy of BazarrCredentialsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$BazarrCredentialsModelCopyWith<_BazarrCredentialsModel> get copyWith =>
      __$BazarrCredentialsModelCopyWithImpl<_BazarrCredentialsModel>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$BazarrCredentialsModelToJson(
      this,
    );
  }

  @override
  String toString() {
    return 'BazarrCredentialsModel(serverUrl: $serverUrl, apiKey: $apiKey)';
  }
}

/// @nodoc
abstract mixin class _$BazarrCredentialsModelCopyWith<$Res>
    implements $BazarrCredentialsModelCopyWith<$Res> {
  factory _$BazarrCredentialsModelCopyWith(_BazarrCredentialsModel value,
          $Res Function(_BazarrCredentialsModel) _then) =
      __$BazarrCredentialsModelCopyWithImpl;
  @override
  @useResult
  $Res call({String serverUrl, String apiKey});
}

/// @nodoc
class __$BazarrCredentialsModelCopyWithImpl<$Res>
    implements _$BazarrCredentialsModelCopyWith<$Res> {
  __$BazarrCredentialsModelCopyWithImpl(this._self, this._then);

  final _BazarrCredentialsModel _self;
  final $Res Function(_BazarrCredentialsModel) _then;

  /// Create a copy of BazarrCredentialsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? serverUrl = null,
    Object? apiKey = null,
  }) {
    return _then(_BazarrCredentialsModel(
      serverUrl: null == serverUrl
          ? _self.serverUrl
          : serverUrl // ignore: cast_nullable_to_non_nullable
              as String,
      apiKey: null == apiKey
          ? _self.apiKey
          : apiKey // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
