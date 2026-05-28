import 'package:flutter/material.dart';

/// Breakpoints used across the app.
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1280;
}

/// Screen size classification.
enum ScreenSize { mobile, tablet, desktop }

/// Extension for quick screen-size access on [BuildContext].
extension ScreenSizeContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isMobile => screenWidth < Breakpoints.mobile;
  bool get isTablet =>
      screenWidth >= Breakpoints.mobile && screenWidth < Breakpoints.tablet;
  bool get isDesktop => screenWidth >= Breakpoints.tablet;
  ScreenSize get screenSize {
    if (screenWidth < Breakpoints.mobile) return ScreenSize.mobile;
    if (screenWidth < Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  /// Columns for chat list grid: 1 on mobile, 2 on tablet, 3 on desktop.
  int get chatListColumns {
    if (isMobile) return 1;
    if (isTablet) return 2;
    return 3;
  }
}

/// Responsive layout that chooses between [mobileLayout] and [desktopLayout].
/// On tablet sizes, [tabletLayout] is used when provided, otherwise falls back
/// to [desktopLayout].
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileLayout;
  final Widget? tabletLayout;
  final Widget desktopLayout;

  const ResponsiveLayout({
    super.key,
    required this.mobileLayout,
    this.tabletLayout,
    required this.desktopLayout,
  });

  // Convenience aliases for legacy code that used `webLayout`.
  static ResponsiveLayout withWeb({
    Key? key,
    required Widget mobileLayout,
    required Widget webLayout,
  }) =>
      ResponsiveLayout(
        key: key,
        mobileLayout: mobileLayout,
        desktopLayout: webLayout,
      );

  // ── Static helpers ──────────────────────────────────────────────────────
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < Breakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= Breakpoints.mobile && w < Breakpoints.tablet;
  }

  static bool isWeb(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.tablet;

  /// Returns the appropriate value based on current screen size.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w < Breakpoints.mobile) return mobile;
    if (w < Breakpoints.tablet) return tablet ?? desktop;
    return desktop;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Breakpoints.tablet) {
          return desktopLayout;
        }
        if (constraints.maxWidth >= Breakpoints.mobile) {
          return tabletLayout ?? desktopLayout;
        }
        return mobileLayout;
      },
    );
  }
}

/// A two-pane layout for tablet/desktop: a fixed-width side panel + main content.
/// On mobile, only [mainContent] is shown (side panel is a drawer).
class TwoPaneLayout extends StatelessWidget {
  final Widget sidePanel;
  final Widget mainContent;
  final double sidePanelWidth;
  final Color? dividerColor;

  const TwoPaneLayout({
    super.key,
    required this.sidePanel,
    required this.mainContent,
    this.sidePanelWidth = 340,
    this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.tablet) {
          // Mobile: full-screen main content
          return mainContent;
        }

        // Tablet / Desktop: two-pane
        return Row(
          children: [
            SizedBox(
              width: sidePanelWidth,
              child: sidePanel,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: dividerColor ?? const Color(0xFFE8EBF0),
            ),
            Expanded(child: mainContent),
          ],
        );
      },
    );
  }
}

/// Padding that adapts to screen size.
class ResponsivePadding extends StatelessWidget {
  final Widget child;
  final EdgeInsets mobile;
  final EdgeInsets? tablet;
  final EdgeInsets desktop;

  const ResponsivePadding({
    super.key,
    required this.child,
    this.mobile = const EdgeInsets.all(16),
    this.tablet,
    this.desktop = const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveLayout.value<EdgeInsets>(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
    return Padding(padding: padding, child: child);
  }
}

/// SizedBox whose size adapts to screen size.
class ResponsiveSizedBox extends StatelessWidget {
  final double mobileSize;
  final double? tabletSize;
  final double desktopSize;
  final Axis axis;

  const ResponsiveSizedBox.height({
    super.key,
    required this.mobileSize,
    this.tabletSize,
    required this.desktopSize,
  }) : axis = Axis.vertical;

  const ResponsiveSizedBox.width({
    super.key,
    required this.mobileSize,
    this.tabletSize,
    required this.desktopSize,
  }) : axis = Axis.horizontal;

  @override
  Widget build(BuildContext context) {
    final size = ResponsiveLayout.value<double>(
      context,
      mobile: mobileSize,
      tablet: tabletSize,
      desktop: desktopSize,
    );
    return axis == Axis.vertical
        ? SizedBox(height: size)
        : SizedBox(width: size);
  }
}
