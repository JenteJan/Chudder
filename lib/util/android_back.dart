import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Keeps every Android back gesture coming to the app.
///
/// With predictive back on, Android only hands a back to Flutter while the
/// framework has said it can use one; otherwise the system closes the app
/// without asking. Flutter's own bookkeeping takes that answer from whichever
/// navigator spoke last, and the app has many: one per tab, nested routers in
/// settings, navigators in sheets. A tab's navigator being built for the first
/// time, or one changing off screen, says "nothing to pop" for itself and
/// overrules a tab that still holds pages - and the next back closed the app
/// from the middle of a details page, until a restart set the answer straight.
///
/// So the app always takes the back. auto_route pops the page on top, Home's
/// own back handling leaves on the first tab's root page, and a back nothing
/// wanted closes the app through Flutter's own fallback. Only the system's
/// back-to-home preview at the very root is given up for it.
bool keepBackInApp(NavigationNotification notification) {
  if (_isAndroid) SystemNavigator.setFrameworkHandlesBack(true);
  return true;
}

/// Says it again whenever the app comes back to the screen: a recreated
/// activity starts out without it, and no navigator speaks until something is
/// pushed or popped.
class AndroidBackOwner extends StatefulWidget {
  final Widget child;
  const AndroidBackOwner({required this.child, super.key});

  @override
  State<AndroidBackOwner> createState() => _AndroidBackOwnerState();
}

class _AndroidBackOwnerState extends State<AndroidBackOwner> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    if (!_isAndroid) return;
    _listener = AppLifecycleListener(onResume: () => SystemNavigator.setFrameworkHandlesBack(true));
    WidgetsBinding.instance.addPostFrameCallback((_) => SystemNavigator.setFrameworkHandlesBack(true));
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
