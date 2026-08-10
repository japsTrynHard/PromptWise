import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int order;

  const FadeSlideIn({super.key, required this.child, this.order = 0});

  @override
  Widget build(BuildContext context) {
    final duration = Duration(
      milliseconds: 280 + (order * 45).clamp(0, 260).toInt(),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.standardCurve,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 14),
            child: child,
          ),
        );
      },
    );
  }
}
