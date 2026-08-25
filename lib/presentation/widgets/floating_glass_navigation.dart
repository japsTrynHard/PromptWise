import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

class GlassNavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const GlassNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// True overlay navigation for learner root tabs.
///
/// This widget owns only the glass island itself. It does not create a bottom
/// bar surface or reserve page height. The dashboard positions it over the
/// scrolling page using a Stack.
class FloatingGlassNavigation extends StatelessWidget {
  final int selectedIndex;
  final List<GlassNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final bool showSelectedLabel;
  final bool minimized;

  const FloatingGlassNavigation({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    this.showSelectedLabel = false,
    this.minimized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final duration = AppMotion.duration(context, AppMotion.normal);

    return IgnorePointer(
      ignoring: destinations.isEmpty,
      child: AnimatedPadding(
        duration: duration,
        curve: AppMotion.standardCurve,
        padding: EdgeInsets.fromLTRB(
          minimized ? 30 : 16,
          6,
          minimized ? 30 : 16,
          bottomInset > 0 ? 9 : 16,
        ),
        child: Center(
          child: AnimatedScale(
            scale: minimized ? 0.94 : 1,
            duration: duration,
            curve: AppMotion.standardCurve,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: minimized ? 510 : 560),
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 19, sigmaY: 19),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: AppMotion.standardCurve,
                      height: minimized ? 56 : 64,
                      padding: EdgeInsets.all(minimized ? 5 : 6),
                      decoration: BoxDecoration(
                        color: (isDark
                                ? const Color(0xFF0F172A)
                                : Colors.white)
                            .withValues(alpha: isDark ? 0.74 : 0.70),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: isDark ? 0.44 : 0.72,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.20 : 0.085,
                            ),
                            blurRadius: minimized ? 21 : 27,
                            offset: Offset(0, minimized ? 9 : 12),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          for (var index = 0;
                              index < destinations.length;
                              index++)
                            Expanded(
                              child: _GlassDestinationButton(
                                destination: destinations[index],
                                selected: selectedIndex == index,
                                compact: minimized,
                                showLabel: showSelectedLabel && !minimized,
                                onTap: () => onSelected(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassDestinationButton extends StatefulWidget {
  final GlassNavDestination destination;
  final bool selected;
  final bool compact;
  final bool showLabel;
  final VoidCallback onTap;

  const _GlassDestinationButton({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.showLabel,
    required this.onTap,
  });

  @override
  State<_GlassDestinationButton> createState() =>
      _GlassDestinationButtonState();
}

class _GlassDestinationButtonState extends State<_GlassDestinationButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final animate = AppMotion.animationsEnabled(context);
    final scale = !animate
        ? 1.0
        : _pressed
            ? 0.94
            : _hovered
                ? 1.02
                : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.duration(context, AppMotion.fast),
        curve: AppMotion.standardCurve,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Semantics(
            button: true,
            selected: widget.selected,
            label: widget.destination.label,
            child: Tooltip(
              message: widget.destination.label,
              waitDuration: const Duration(milliseconds: 450),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: (value) {
                    if (_pressed == value) return;
                    setState(() => _pressed = value);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: AnimatedContainer(
                    duration: AppMotion.duration(context, AppMotion.normal),
                    curve: AppMotion.standardCurve,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.showLabel && widget.selected ? 10 : 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      color: widget.selected
                          ? primary.withValues(alpha: 0.10)
                          : _hovered
                              ? primary.withValues(alpha: 0.035)
                              : Colors.transparent,
                      border: widget.selected
                          ? Border.all(
                              color: primary.withValues(alpha: 0.12),
                            )
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: widget.selected ? 1.04 : 1,
                            duration:
                                AppMotion.duration(context, AppMotion.fast),
                            curve: AppMotion.standardCurve,
                            child: Icon(
                              widget.selected
                                  ? widget.destination.selectedIcon
                                  : widget.destination.icon,
                              size: widget.compact ? 20 : 23,
                              color: widget.selected
                                  ? primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.showLabel && widget.selected) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
