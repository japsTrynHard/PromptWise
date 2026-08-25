import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

enum AppWindowSize { compact, medium, expanded, large }

class AdaptiveLayout {
  AdaptiveLayout._();

  static AppWindowSize sizeFor(double width) {
    if (width < AppBreakpoints.compact) return AppWindowSize.compact;
    if (width < AppBreakpoints.tablet) return AppWindowSize.medium;
    if (width < AppBreakpoints.desktop) return AppWindowSize.expanded;
    return AppWindowSize.large;
  }

  static AppWindowSize sizeOf(BuildContext context) {
    return sizeFor(MediaQuery.sizeOf(context).width);
  }

  static bool isCompact(BuildContext context) {
    return sizeOf(context) == AppWindowSize.compact;
  }

  static bool isNarrowPhone(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 360;
  }

  /// Uses shortestSide so a phone in landscape is still treated as a phone.
  static bool isPhoneFormFactor(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide < 600;
  }

  static bool isTabletFormFactor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= 600 && size.width < AppBreakpoints.desktop;
  }

  static bool isAtLeastTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  /// Navigation rail should not appear just because an iPhone is rotated.
  /// Tablets can use a rail from 720 logical pixels; wide desktop windows
  /// always use it.
  static bool prefersRailNavigation(
    BuildContext context, {
    required double availableWidth,
  }) {
    if (availableWidth >= AppBreakpoints.desktop) {
      return true;
    }

    return MediaQuery.sizeOf(context).shortestSide >= 600 &&
        availableWidth >= 720;
  }

  static double horizontalPaddingFor(double width) {
    if (width < 340) return AppSpacing.md;
    if (width < 430) return AppSpacing.lg;
    if (width < AppBreakpoints.compact) return AppSpacing.xl;
    if (width < AppBreakpoints.tablet) return AppSpacing.xxl;
    return AppSpacing.section;
  }

  static EdgeInsets pageInsets(
    BuildContext context, {
    double top = AppSpacing.page,
    double bottom = AppSpacing.section,
  }) {
    final horizontal = horizontalPaddingFor(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  static int gridColumns(
    double width, {
    double minimumTileWidth = 280,
    int maximumColumns = 4,
  }) {
    final possible = (width / minimumTileWidth).floor();
    return possible.clamp(1, maximumColumns).toInt();
  }
}

/// Centers a screen and prevents learner content from stretching excessively on
/// large browser windows while still using the full width on phones and tablets.
class AdaptiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool useSafeArea;
  final bool safeTop;
  final bool safeBottom;

  const AdaptiveBody({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.useSafeArea = true,
    this.safeTop = true,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = LayoutBuilder(
      builder: (context, constraints) {
        final boundedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final targetWidth = boundedWidth < maxWidth ? boundedWidth : maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: targetWidth,
            child: child,
          ),
        );
      },
    );

    if (useSafeArea) {
      result = SafeArea(
        top: safeTop,
        bottom: safeBottom,
        child: result,
      );
    }

    return result;
  }
}
