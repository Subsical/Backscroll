import 'package:flutter/material.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({this.thickness = 4});

  final double thickness;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) return child;
    return switch (getPlatform(context)) {
      TargetPlatform.linux || TargetPlatform.windows => _HoverScrollbar(
        controller: details.controller,
        thickness: thickness,
        child: child,
      ),
      _ => child,
    };
  }

  @override
  bool shouldNotify(AppScrollBehavior oldDelegate) =>
      oldDelegate.thickness != thickness;
}

class _HoverScrollbar extends StatefulWidget {
  const _HoverScrollbar({
    required this.controller,
    required this.thickness,
    required this.child,
  });

  final ScrollController? controller;
  final double thickness;
  final Widget child;

  @override
  State<_HoverScrollbar> createState() => _HoverScrollbarState();
}

class _HoverScrollbarState extends State<_HoverScrollbar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: RawScrollbar(
      controller: widget.controller,
      thumbVisibility: _hover,
      thumbColor: const Color(0xFF767780),
      thickness: widget.thickness,
      radius: Radius.circular(widget.thickness / 2),
      crossAxisMargin: widget.thickness / 2,
      mainAxisMargin: widget.thickness / 2,
      minThumbLength: 40,
      fadeDuration: Duration.zero,
      timeToFade: Duration.zero,
      child: widget.child,
    ),
  );
}
