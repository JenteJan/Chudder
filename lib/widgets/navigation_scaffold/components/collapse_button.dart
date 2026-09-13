import 'package:flutter/material.dart';

import 'package:chudder/widgets/shared/focus_ring.dart';

class CollapseButton extends StatefulWidget {
  final Widget? label;
  final Widget icon;
  final bool keepVisible;
  final Function() onPressed;
  const CollapseButton({
    required this.label,
    required this.icon,
    this.keepVisible = false,
    required this.onPressed,
    super.key,
  });

  @override
  State<CollapseButton> createState() => _CollapseButtonState();
}

class _CollapseButtonState extends State<CollapseButton> {
  bool hovering = false;
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onPressed,
        onHover: (value) {
          setState(() {
            hovering = value;
          });
        },
        onFocusChange: (value) {
          setState(() {
            focused = value;
          });
        },
        // Brightening alone is not a selection you can see from a sofa; the
        // ring is.
        child: FocusRing(
          visible: focused,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: hovering || focused ? 1 : 0.5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.label != null) widget.label!,
                if (widget.keepVisible)
                  widget.icon
                else
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: hovering || focused ? 1.0 : 0.0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      offset: hovering || focused ? Offset.zero : const Offset(-1, 0),
                      child: widget.icon,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
