// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'jellybot_search_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$JellybotSearchState {
  String get query;
  MediaCategory get category;
  IProvider? get provider;
  Map<String, String> get selectedFilters;
  bool get exactMatch;
  double? get minScore;
  int get page;
  int get pageSize;

  /// Create a copy of JellybotSearchState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $JellybotSearchStateCopyWith<JellybotSearchState> get copyWith =>
      _$JellybotSearchStateCopyWithImpl<JellybotSearchState>(
          this as JellybotSearchState, _$identity);

  @override
  String toString() {
    return 'JellybotSearchState(query: $query, category: $category, provider: $provider, selectedFilters: $selectedFilters, exactMatch: $exactMatch, minScore: $minScore, page: $page, pageSize: $pageSize)';
  }
}

/// @nodoc
abstract mixin class $JellybotSearchStateCopyWith<$Res> {
  factory $JellybotSearchStateCopyWith(
          JellybotSearchState value, $Res Function(JellybotSearchState) _then) =
      _$JellybotSearchStateCopyWithImpl;
  @useResult
  $Res call(
      {String query,
      MediaCategory category,
      IProvider? provider,
      Map<String, String> selectedFilters,
      bool exactMatch,
      double? minScore,
      int page,
      int pageSize});
}

/// @nodoc
class _$JellybotSearchStateCopyWithImpl<$Res>
    implements $JellybotSearchStateCopyWith<$Res> {
  _$JellybotSearchStateCopyWithImpl(this._self, this._then);

  final JellybotSearchState _self;
  final $Res Function(JellybotSearchState) _then;

  /// Create a copy of JellybotSearchState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? query = null,
    Object? category = null,
    Object? provider = freezed,
    Object? selectedFilters = null,
    Object? exactMatch = null,
    Object? minScore = freezed,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(_self.copyWith(
      query: null == query
          ? _self.query
          : query // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _self.category
          : category // ignore: cast_nullable_to_non_nullable
              as MediaCategory,
      provider: freezed == provider
          ? _self.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as IProvider?,
      selectedFilters: null == selectedFilters
          ? _self.selectedFilters
          : selectedFilters // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      exactMatch: null == exactMatch
          ? _self.exactMatch
          : exactMatch // ignore: cast_nullable_to_non_nullable
              as bool,
      minScore: freezed == minScore
          ? _self.minScore
          : minScore // ignore: cast_nullable_to_non_nullable
              as double?,
      page: null == page
          ? _self.page
          : page // ignore: cast_nullable_to_non_nullable
              as int,
      pageSize: null == pageSize
          ? _self.pageSize
          : pageSize // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [JellybotSearchState].
extension JellybotSearchStatePatterns on JellybotSearchState {
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
    TResult Function(_JellybotSearchState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState() when $default != null:
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
    TResult Function(_JellybotSearchState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState():
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
    TResult? Function(_JellybotSearchState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState() when $default != null:
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
    TResult Function(
            String query,
            MediaCategory category,
            IProvider? provider,
            Map<String, String> selectedFilters,
            bool exactMatch,
            double? minScore,
            int page,
            int pageSize)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState() when $default != null:
        return $default(
            _that.query,
            _that.category,
            _that.provider,
            _that.selectedFilters,
            _that.exactMatch,
            _that.minScore,
            _that.page,
            _that.pageSize);
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
    TResult Function(
            String query,
            MediaCategory category,
            IProvider? provider,
            Map<String, String> selectedFilters,
            bool exactMatch,
            double? minScore,
            int page,
            int pageSize)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState():
        return $default(
            _that.query,
            _that.category,
            _that.provider,
            _that.selectedFilters,
            _that.exactMatch,
            _that.minScore,
            _that.page,
            _that.pageSize);
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
    TResult? Function(
            String query,
            MediaCategory category,
            IProvider? provider,
            Map<String, String> selectedFilters,
            bool exactMatch,
            double? minScore,
            int page,
            int pageSize)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _JellybotSearchState() when $default != null:
        return $default(
            _that.query,
            _that.category,
            _that.provider,
            _that.selectedFilters,
            _that.exactMatch,
            _that.minScore,
            _that.page,
            _that.pageSize);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _JellybotSearchState extends JellybotSearchState {
  const _JellybotSearchState(
      {this.query = '',
      this.category = MediaCategory.movie,
      this.provider,
      final Map<String, String> selectedFilters = const <String, String>{},
      this.exactMatch = false,
      this.minScore,
      this.page = 0,
      this.pageSize = 20})
      : _selectedFilters = selectedFilters,
        super._();

  @override
  @JsonKey()
  final String query;
  @override
  @JsonKey()
  final MediaCategory category;
  @override
  final IProvider? provider;
  final Map<String, String> _selectedFilters;
  @override
  @JsonKey()
  Map<String, String> get selectedFilters {
    if (_selectedFilters is EqualUnmodifiableMapView) return _selectedFilters;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_selectedFilters);
  }

  @override
  @JsonKey()
  final bool exactMatch;
  @override
  final double? minScore;
  @override
  @JsonKey()
  final int page;
  @override
  @JsonKey()
  final int pageSize;

  /// Create a copy of JellybotSearchState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$JellybotSearchStateCopyWith<_JellybotSearchState> get copyWith =>
      __$JellybotSearchStateCopyWithImpl<_JellybotSearchState>(
          this, _$identity);

  @override
  String toString() {
    return 'JellybotSearchState(query: $query, category: $category, provider: $provider, selectedFilters: $selectedFilters, exactMatch: $exactMatch, minScore: $minScore, page: $page, pageSize: $pageSize)';
  }
}

/// @nodoc
abstract mixin class _$JellybotSearchStateCopyWith<$Res>
    implements $JellybotSearchStateCopyWith<$Res> {
  factory _$JellybotSearchStateCopyWith(_JellybotSearchState value,
          $Res Function(_JellybotSearchState) _then) =
      __$JellybotSearchStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String query,
      MediaCategory category,
      IProvider? provider,
      Map<String, String> selectedFilters,
      bool exactMatch,
      double? minScore,
      int page,
      int pageSize});
}

/// @nodoc
class __$JellybotSearchStateCopyWithImpl<$Res>
    implements _$JellybotSearchStateCopyWith<$Res> {
  __$JellybotSearchStateCopyWithImpl(this._self, this._then);

  final _JellybotSearchState _self;
  final $Res Function(_JellybotSearchState) _then;

  /// Create a copy of JellybotSearchState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? query = null,
    Object? category = null,
    Object? provider = freezed,
    Object? selectedFilters = null,
    Object? exactMatch = null,
    Object? minScore = freezed,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(_JellybotSearchState(
      query: null == query
          ? _self.query
          : query // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _self.category
          : category // ignore: cast_nullable_to_non_nullable
              as MediaCategory,
      provider: freezed == provider
          ? _self.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as IProvider?,
      selectedFilters: null == selectedFilters
          ? _self._selectedFilters
          : selectedFilters // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      exactMatch: null == exactMatch
          ? _self.exactMatch
          : exactMatch // ignore: cast_nullable_to_non_nullable
              as bool,
      minScore: freezed == minScore
          ? _self.minScore
          : minScore // ignore: cast_nullable_to_non_nullable
              as double?,
      page: null == page
          ? _self.page
          : page // ignore: cast_nullable_to_non_nullable
              as int,
      pageSize: null == pageSize
          ? _self.pageSize
          : pageSize // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
