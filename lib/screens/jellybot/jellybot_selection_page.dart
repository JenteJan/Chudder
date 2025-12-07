import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// Empty page shown in single-pane mode when no tab is selected
@RoutePage()
class JellybotSelectionPage extends StatelessWidget {
  const JellybotSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
