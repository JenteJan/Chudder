import 'package:fladder/util/platform_helper.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'arguments_model.freezed.dart';

/// Prefer using the arguments provider over this boolean
bool leanBackMode = false;

/// Indicates if running on Tizen platform (Samsung TV)
bool tizenMode = PlatformHelper.isTizen;

@freezed
abstract class ArgumentsModel with _$ArgumentsModel {
  const ArgumentsModel._();

  factory ArgumentsModel({
    @Default(false) bool htpcMode,
    @Default(false) bool leanBackMode,
    @Default(false) bool tizenMode,
    @Default(false) bool newWindow,
  }) = _ArgumentsModel;

  factory ArgumentsModel.fromArguments(List<String> arguments, String windowArguments, bool leanBackEnabled) {
    arguments = arguments.map((e) => e.trim()).toList();
    leanBackMode = leanBackEnabled;
    final parsedWindowArgs = windowArguments.split(',');
    final isTizen = PlatformHelper.isTizen;
    return ArgumentsModel(
      htpcMode: arguments.contains('--htpc') || leanBackEnabled || isTizen,
      leanBackMode: leanBackEnabled,
      tizenMode: isTizen,
      newWindow: parsedWindowArgs.contains('--newWindow'),
    );
  }
}
