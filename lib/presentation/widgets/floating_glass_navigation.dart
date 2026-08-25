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

/// Floating learner navigation for phone-sized layouts.
///
/// Important: the root has an explicit finite height. An unconstrained Center
/// inside Scaffold.bottomNavigationBar can consume the whole scaffold height on
/// iOS/Android and narrow web layouts, leaving only the navigation island visible.
class FloatingGlassNavigation extends StatelessWidget {
  static const double surfaceHeight = 70;

  final int selectedIndex;
  final List<GlassNavDestination> destinations;
  final ValueChanged<int> onSelected;

  const FloatingGlassNavigation({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = screenWidth < 360 ? AppSpacing.sm : AppSpacing.md;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal,
          AppSpacing.xs,
          horizontal,
          0,
        ),
        child: SizedBox(
          height: surfaceHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 590),
              child: SizedBox(
                width: double.infinity,
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? const Color(0xFF111827)
                                  : Colors.white)
                              .withValues(alpha: isDark ? 0.88 : 0.84),
                          borderRadius: BorderRadius.circular(34),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: isDark ? 0.56 : 0.84,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.22 : 0.085,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (destinations.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final count = destinations.length;
                              final showSelectedLabel =
                                  constraints.maxWidth >= 340;
                              final selectedFlex =
                                  showSelectedLabel ? 1.72 : 1.0;
                              final denominator =
                                  (count - 1) + selectedFlex;
                              final unit = constraints.maxWidth / denominator;
                              final inactiveWidth = unit;
                              final selectedWidth = unit * selectedFlex;

                              return SizedBox(
                                height: 58,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var index = 0;
                                        index < count;
                                        index++)
                                      _GlassDestinationButton(
                                        destination: destinations[index],
                                        selected: selectedIndex == index,
                                        width: selectedIndex == index
                                            ? selectedWidth
                                            : inactiveWidth,
                                        showLabel: showSelectedLabel,
                                        onTap: () => onSelected(index),
                                      ),
                                  ],
                                ),
                              );
                            },
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
      ),
    );
  }
}

class _GlassDestinationButton extends StatefulWidget {
  final GlassNavDestination destination;
  final bool selected;
  final double width;
  final bool showLabel;
  final VoidCallback onTap;

  const _GlassDestinationButton({
    required this.destination,
    required this.selected,
    required this.width,
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
            ? 0.955
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
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standardCurve,
          width: widget.width,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 3),
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
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      gradient: widget.selected
                          ? LinearGradient(
                              colors: [
                                primary.withValues(alpha: 0.17),
                                AppColors.violet.withValues(alpha: 0.12),
                              ],
                            )
                          : _hovered
                              ? LinearGradient(
                                  colors: [
                                    primary.withValues(alpha: 0.055),
                                    primary.withValues(alpha: 0.025),
                                  ],
                                )
                              : null,
                      border: widget.selected
                          ? Border.all(
                              color: primary.withValues(alpha: 0.18),
                            )
                          : null,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          widget.selected && widget.showLabel ? 9 : 5,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: widget.selected ? 1.06 : 1,
                          duration: AppMotion.duration(
                            context,
                            AppMotion.fast,
                          ),
                          curve: AppMotion.standardCurve,
                          child: Icon(
                            widget.selected
                                ? widget.destination.selectedIcon
                                : widget.destination.icon,
                            size: 23,
                            color: widget.selected
                                ? primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.showLabel)
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: AppMotion.duration(
                                context,
                                AppMotion.normal,
                              ),
                              switchInCurve: AppMotion.standardCurve,
                              switchOutCurve: AppMotion.reverseCurve,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  axis: Axis.horizontal,
                                  sizeFactor: animation,
                                  child: child,
                                ),
                              ),
                              child: widget.selected
                                  ? Padding(
                                      key: ValueKey(widget.destination.label),
                                      padding: const EdgeInsets.only(left: 7),
                                      child: Text(
                                        widget.destination.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('inactive'),
                                    ),
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
    );
  }
}
