import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';

/// Whether this session is being driven from a sofa rather than a desk.
final tvControlsProvider = Provider<bool>((ref) {
  return ref.watch(argumentsStateProvider.select((value) => value.htpcMode || value.leanBackMode));
});

/// Whether what is open should carry television controls right now.
///
/// The launch flags say how the session was started; the input device says
/// what is in the user's hand this minute. A desktop driven with the arrow
/// keys is a pad, and every dialog and sheet needs its way out then too - the
/// flags alone left them all without one.
bool tvControlsOf(BuildContext context, WidgetRef ref) =>
    // read, not watch: the flags never change after launch, and this is asked
    // from lifecycle callbacks as well as build. The input device is an
    // inherited lookup, which rebuilds the asker when it changes.
    ref.read(tvControlsProvider) || AdaptiveLayout.maybeOf(context)?.data.inputDevice == InputDevice.dPad;

/// A close button that belongs to the dialog it sits in.
///
/// Nothing at all anywhere but a television, so it can be dropped into any
/// header unconditionally.
///
/// It is one button and not a button inside a [Focus]: an Activate - what the
/// select key sends - is delivered to the node that holds focus, so a wrapper
/// node around a button takes the selection and then has nothing to do with it.
/// The focus is watched from an ancestor that cannot hold it instead.
class TvDialogClose extends ConsumerWidget {
  const TvDialogClose({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!tvControlsOf(context, ref)) return const SizedBox.shrink();

    // Deliberately unstyled: iconButtonTheme already carries the app's focus
    // treatment, and giving this one a fill of its own made it the only button
    // in any dialog that showed selection differently to the rest.
    return Tooltip(
      message: context.localized.close,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}

/// Puts a close button on the top-right of a dialog's own surface.
///
/// Wraps the dialog's *content*, not the dialog: a Stack takes the size of its
/// child, so from in there the corner it pins to is the card's corner rather
/// than the screen's, and the button reads as part of the dialog instead of
/// something floating over it.
class TvDialogSurface extends ConsumerWidget {
  final Widget child;

  /// Room to leave for the button, when the content would otherwise run under
  /// it. Dialogs with a title line rarely need any.
  final EdgeInsets contentPadding;

  const TvDialogSurface({required this.child, this.contentPadding = EdgeInsets.zero, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!tvControlsOf(context, ref)) return child;

    return Stack(
      children: [
        Padding(padding: contentPadding, child: child),
        const Positioned(top: 4, right: 4, child: TvDialogClose()),
      ],
    );
  }
}

/// Keeps the pad inside what is open, and lets back close it.
///
/// Without this the pad walks out of the dialog and into the player behind it,
/// which is invisible under the barrier: the selection simply vanishes and
/// nothing responds.
class TvDialogFrame extends ConsumerStatefulWidget {
  final Widget child;

  /// Kept for call sites that pass it; the frame no longer lays anything out.
  final bool fill;

  const TvDialogFrame({required this.child, this.fill = true, super.key});

  @override
  ConsumerState<TvDialogFrame> createState() => _TvDialogFrameState();
}

class _TvDialogFrameState extends ConsumerState<TvDialogFrame> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'tvDialog');

  @override
  void initState() {
    super.initState();
    // A scope given autofocus takes the focus itself and stops there, leaving
    // the selection on nothing: there is no control to see it on and no control
    // to move away from, so the pad appears dead. Put it on something real.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !tvControlsOf(context, ref)) return;
      if (_scope.focusedChild != null) return;
      _scope.nextFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing at a desk. Escape already dismisses these there, and taking the
    // key first would only risk closing two things at once.
    if (!tvControlsOf(context, ref)) return widget.child;

    return FocusScope(
      node: _scope,
      // Pulls the selection off whatever held it underneath and into here.
      autofocus: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.escape && event.logicalKey != LogicalKeyboardKey.goBack) {
            return KeyEventResult.ignored;
          }
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        },
        child: widget.child,
      ),
    );
  }
}

/// The focus half on its own, for a sheet that hosts its own close button.
class TvModalScope extends StatelessWidget {
  final Widget child;

  const TvModalScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) => TvDialogFrame(child: child);
}
