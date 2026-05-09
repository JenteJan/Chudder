// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_provider_alist.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$UpdatesModelAlist {
  List<ReleaseInfo> get lastRelease;
  Map<String, AlistReleaseExtras> get extras;

  @override
  String toString() {
    return 'UpdatesModelAlist(lastRelease: $lastRelease, extras: $extras)';
  }
}

/// Adds pattern-matching-related methods to [UpdatesModelAlist].
extension UpdatesModelAlistPatterns on UpdatesModelAlist {
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
    TResult Function(_UpdatesModelAlist value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist() when $default != null:
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
    TResult Function(_UpdatesModelAlist value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist():
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
    TResult? Function(_UpdatesModelAlist value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist() when $default != null:
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
    TResult Function(List<ReleaseInfo> lastRelease,
            Map<String, AlistReleaseExtras> extras)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist() when $default != null:
        return $default(_that.lastRelease, _that.extras);
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
    TResult Function(List<ReleaseInfo> lastRelease,
            Map<String, AlistReleaseExtras> extras)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist():
        return $default(_that.lastRelease, _that.extras);
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
    TResult? Function(List<ReleaseInfo> lastRelease,
            Map<String, AlistReleaseExtras> extras)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _UpdatesModelAlist() when $default != null:
        return $default(_that.lastRelease, _that.extras);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _UpdatesModelAlist extends UpdatesModelAlist {
  const _UpdatesModelAlist(
      {final List<ReleaseInfo> lastRelease = const [],
      final Map<String, AlistReleaseExtras> extras = const {}})
      : _lastRelease = lastRelease,
        _extras = extras,
        super._();

  final List<ReleaseInfo> _lastRelease;
  @override
  @JsonKey()
  List<ReleaseInfo> get lastRelease {
    if (_lastRelease is EqualUnmodifiableListView) return _lastRelease;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_lastRelease);
  }

  final Map<String, AlistReleaseExtras> _extras;
  @override
  @JsonKey()
  Map<String, AlistReleaseExtras> get extras {
    if (_extras is EqualUnmodifiableMapView) return _extras;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_extras);
  }

  @override
  String toString() {
    return 'UpdatesModelAlist(lastRelease: $lastRelease, extras: $extras)';
  }
}

// dart format on
