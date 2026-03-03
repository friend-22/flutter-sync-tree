import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A custom [SingleChildScrollView] that enables mouse/trackpad dragging
/// and disables the overscroll glow across all platforms.
///
/// This is particularly useful for desktop and web examples where
/// natural scrolling behavior with a mouse is expected.
class AdaptiveScrollView extends SingleChildScrollView {
  const AdaptiveScrollView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.padding,
    super.primary,
    super.physics,
    super.controller,
    super.child,
    super.dragStartBehavior,
    super.clipBehavior,
    super.hitTestBehavior,
    super.restorationId,
    super.keyboardDismissBehavior,
  });

  @override
  Widget build(BuildContext context) {
    // Applying a custom ScrollBehavior to support multiple input devices.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        // Set to false to maintain a clean UI in example apps.
        overscroll: false,
      ),
      child: Builder(
        // We use a Builder to ensure the correct context is used for super.build
        builder: (context) => super.build(context),
      ),
    );
  }
}
