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

/// Floating learner navigation for compact screens.
///
/// The control is designed to sit above page content like a floating glass
/// island. It should be overlaid in a [Stack] instead of occupying layout
/// space like a traditional bottom navigation bar.
class FloatingGlassNavigation extends StatelessWidget {
  final int selectedIndex;
  final List<GlassNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final bool showSelectedLabel;

  const FloatingGlassNavigation({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    this.showSelectedLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return IgnorePointer(
      ignoring: destinations.isEmpty,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          bottomInset > 0 ? 10 : 18,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF0F172A) : Colors.white)
                          .withValues(alpha: isDark ? 0.78 : 0.72),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: isDark ? 0.52 : 0.82,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.24 : 0.1,
                          ),
                          blurRadius: 32,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: SizedBox(
                        height: 58,
                        child: Row(
                          children: [
                            for (var index = 0; index < destinations.length; index++)
                              Expanded(
                                child: _GlassDestinationButton(
                                  destination: destinations[index],
                                  selected: selectedIndex == index,
                                  showLabel: showSelectedLabel,
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
      ),
    );
  }
}

class _GlassDestinationButton extends StatefulWidget {
  final GlassNavDestination destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  const _GlassDestinationButton({
    required this.destination,
    required this.selected,
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
            ? 0.96
            : _hovered
                ? 1.015
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
              waitDuration: const Duration(milliseconds: 500),
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
                      horizontal: widget.showLabel && widget.selected ? 12 : 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      gradient: widget.selected
                          ? LinearGradient(
                              colors: [
                                primary.withValues(alpha: 0.16),
                                AppColors.violet.withValues(alpha: 0.1),
                              ],
                            )
                          : _hovered
                              ? LinearGradient(
                                  colors: [
                                    primary.withValues(alpha: 0.045),
                                    primary.withValues(alpha: 0.02),
                                  ],
                                )
                              : null,
                      border: widget.selected
                          ? Border.all(
                              color: primary.withValues(alpha: 0.17),
                            )
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.selected
                                ? widget.destination.selectedIcon
                                : widget.destination.icon,
                            size: 24,
                            color: widget.selected
                                ? primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          if (widget.showLabel && widget.selected) ...[
                            const SizedBox(width: 7),
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
