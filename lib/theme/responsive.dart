import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Window size classes (Material 3 guidance) used across the app.
///
/// - compact:  narrow phones, under 360 dp wide (e.g. 320 dp)
/// - medium:   most phones in portrait, 360–599 dp
/// - expanded: landscape phones, foldables and tablets, 600 dp and up
enum WindowSize { compact, medium, expanded }

class Responsive {
  const Responsive._();

  /// Readable content width on wide screens; content is centred beyond it.
  static const maxContentWidth = 680.0;

  /// Largest system text scale the layouts are designed for. Larger system
  /// settings are honoured up to this point so no screen has to clip text.
  static const maxTextScale = 1.4;

  static WindowSize sizeOf(BuildContext context) =>
      sizeFor(MediaQuery.sizeOf(context).width);

  static WindowSize sizeFor(double width) => width < 360
      ? WindowSize.compact
      : width < 600
      ? WindowSize.medium
      : WindowSize.expanded;

  /// Side gutter of scrolling pages.
  static double gutter(BuildContext context) => switch (sizeOf(context)) {
    WindowSize.compact => 12,
    WindowSize.medium => 16,
    WindowSize.expanded => 24,
  };

  /// Inner padding of cards.
  static double cardPadding(BuildContext context) =>
      sizeOf(context) == WindowSize.compact ? 12 : 16;

  /// Gap between stacked cards.
  static double sectionGap(BuildContext context) =>
      sizeOf(context) == WindowSize.compact ? 12 : 16;

  /// Current text scale factor (1.0 = default system font size).
  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) / 10;

  /// Horizontal padding that centres content of at most [maxContentWidth]
  /// and keeps it clear of display cut-outs in landscape.
  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final g = gutter(context);
    final side = math.max(g, (width - maxContentWidth) / 2);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

/// Scrollable, centred area for full-page messages (access denied, errors)
/// so they never overflow on short screens or in landscape.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
