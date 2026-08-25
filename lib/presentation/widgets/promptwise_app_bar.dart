import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

/// Compact system header for learner detail screens.
///
/// Mobile intentionally keeps only the back control, page title and essential
/// actions. Eyebrows/subtitles stay available on larger layouts so a phone
/// never loses a large portion of its viewport to chrome.
class PromptWiseAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final bool showBack;
  final String backTooltip;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const PromptWiseAppBar({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.showBack = true,
    this.backTooltip = 'Back',
    this.onBack,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).shortestSide < AppBreakpoints.compact;
    final toolbarHeight = compact ? 54.0 : 62.0;
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      flexibleSpace: RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor.withValues(
                alpha: isDark ? 0.86 : 0.90,
              ),
            ),
          ),
        ),
      ),
      leadingWidth: showBack ? (compact ? 54 : 62) : 0,
      leading: showBack
          ? Padding(
              padding: EdgeInsets.only(
                left: compact ? AppSpacing.md : AppSpacing.lg,
                top: 8,
                bottom: 8,
              ),
              child: _PromptWiseBackButton(
                tooltip: backTooltip,
                onPressed: onBack ?? () => Navigator.maybePop(context),
              ),
            )
          : null,
      titleSpacing: showBack ? AppSpacing.sm : AppSpacing.lg,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact && eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
            Text(
              eyebrow!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.65,
              ),
            ),
            const SizedBox(height: 1),
          ],
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge)
                ?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: compact ? 18 : null,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
              height: 1.08,
            ),
          ),
          if (!compact && subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...actions,
        SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
    );
  }
}

class PromptWiseHeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const PromptWiseHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _MotionCircleButton(
        tooltip: tooltip,
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 19),
      ),
    );
  }
}

class _PromptWiseBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _PromptWiseBackButton({
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: _MotionCircleButton(
        tooltip: tooltip,
        onPressed: onPressed,
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
    );
  }
}

class _MotionCircleButton extends StatefulWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  const _MotionCircleButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  @override
  State<_MotionCircleButton> createState() => _MotionCircleButtonState();
}

class _MotionCircleButtonState extends State<_MotionCircleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.onPressed != null;
    final animate = enabled && AppMotion.animationsEnabled(context);
    final scale = !animate
        ? 1.0
        : _pressed
            ? 0.93
            : _hovered
                ? 1.03
                : 1.0;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled
            ? (_) => setState(() {
                  _hovered = false;
                  _pressed = false;
                })
            : null,
        child: AnimatedScale(
          scale: scale,
          duration: AppMotion.duration(context, AppMotion.fast),
          curve: AppMotion.standardCurve,
          child: Material(
            color: theme.colorScheme.surface.withValues(
              alpha: _hovered ? 0.90 : 0.62,
            ),
            shape: CircleBorder(
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.68),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onPressed,
              onHighlightChanged: enabled
                  ? (value) {
                      if (_pressed == value) return;
                      setState(() => _pressed = value);
                    }
                  : null,
              child: SizedBox.square(
                dimension: 38,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
