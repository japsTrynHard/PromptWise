import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int order;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.order = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.animationsEnabled(context)) {
      return child;
    }

    // Keep staggered entrances short. Longer list animations look impressive
    // in demos but feel sluggish on phones and while rapidly navigating.
    final stagger = (order * 28).clamp(0, 140).toInt();
    final duration = Duration(milliseconds: 190 + stagger);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.standardCurve,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 9),
            child: child,
          ),
        );
      },
    );
  }
}
