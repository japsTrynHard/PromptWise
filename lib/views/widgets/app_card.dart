import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BorderSide? border;
  final bool animateOnTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.backgroundColor,
    this.border,
    this.animateOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: border ?? BorderSide(color: theme.colorScheme.outlineVariant),
    );
    final content = Padding(padding: padding, child: child);

    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.standardCurve,
      child: Card(
        color: backgroundColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
