import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BorderSide? border;
  final bool animateOnTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.border,
    this.animateOnTap = true,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final interactive = widget.onTap != null;
    final animate = interactive &&
        widget.animateOnTap &&
        AppMotion.animationsEnabled(context);

    final compact = MediaQuery.sizeOf(context).shortestSide < AppBreakpoints.compact;
    final radius = compact ? 18.0 : AppRadius.lg;
    final resolvedPadding = widget.padding ??
        EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: widget.border ?? BorderSide(color: theme.colorScheme.outlineVariant),
    );

    final content = Padding(
      padding: resolvedPadding,
      child: widget.child,
    );

    final card = Card(
      color: widget.backgroundColor,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _setPressed,
              child: content,
            )
          : content,
    );

    final scale = !animate
        ? 1.0
        : _pressed
            ? 0.992
            : _hovered
                ? 1.006
                : 1.0;

    final hoverLift = animate && _hovered && !_pressed;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => _setHovered(true) : null,
      onExit: interactive
          ? (_) {
              _setHovered(false);
              _setPressed(false);
            }
          : null,
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.duration(context, AppMotion.fast),
        curve: AppMotion.standardCurve,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standardCurve,
          transform: Matrix4.translationValues(0, hoverLift ? -2 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: hoverLift
                      ? (isDark ? 0.22 : 0.09)
                      : (isDark ? 0.10 : 0.035),
                ),
                blurRadius: hoverLift ? 24 : 14,
                offset: Offset(0, hoverLift ? 9 : 5),
              ),
            ],
          ),
          child: card,
        ),
      ),
    );
  }
}
