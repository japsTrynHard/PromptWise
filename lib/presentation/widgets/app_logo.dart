import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final bool showTagline;
  final MainAxisAlignment alignment;

  const AppLogo({
    super.key,
    this.size = 64,
    this.showWordmark = true,
    this.showTagline = false,
    this.alignment = MainAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PromptWiseLogoPainter(
          darkMode: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );

    if (!showWordmark) return Semantics(label: 'PromptWise logo', child: mark);

    final wordmark = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment == MainAxisAlignment.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
            children: const [
              TextSpan(text: 'Prompt'),
              TextSpan(
                text: 'Wise',
                style: TextStyle(color: AppColors.teal),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.tagline,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    return Semantics(
      label: 'PromptWise, ${AppStrings.tagline}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignment,
        children: [
          mark,
          const SizedBox(width: AppSpacing.md),
          wordmark,
        ],
      ),
    );
  }
}

class _PromptWiseLogoPainter extends CustomPainter {
  final bool darkMode;

  const _PromptWiseLogoPainter({required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.shortestSide / 100;

    final haloPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: darkMode ? 0.08 : 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 46 * scale, haloPaint);

    final bookPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [AppColors.indigo700, AppColors.primary, AppColors.violet],
      ).createShader(Offset.zero & size);

    final leftBook = Path()
      ..moveTo(12 * scale, 48 * scale)
      ..quadraticBezierTo(28 * scale, 42 * scale, 47 * scale, 58 * scale)
      ..lineTo(47 * scale, 87 * scale)
      ..quadraticBezierTo(28 * scale, 72 * scale, 12 * scale, 77 * scale)
      ..close();
    final rightBook = Path()
      ..moveTo(88 * scale, 48 * scale)
      ..quadraticBezierTo(72 * scale, 42 * scale, 53 * scale, 58 * scale)
      ..lineTo(53 * scale, 87 * scale)
      ..quadraticBezierTo(72 * scale, 72 * scale, 88 * scale, 77 * scale)
      ..close();
    canvas.drawPath(leftBook, bookPaint);
    canvas.drawPath(rightBook, bookPaint);

    final checkPaint = Paint()
      ..color = AppColors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final check = Path()
      ..moveTo(36 * scale, 61 * scale)
      ..lineTo(47 * scale, 71 * scale)
      ..lineTo(66 * scale, 51 * scale);
    canvas.drawPath(check, checkPaint);

    final networkPaint = Paint()
      ..color = darkMode ? const Color(0xFFA5B4FC) : AppColors.indigo700
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    final nodes = <Offset>[
      Offset(center.dx, 10 * scale),
      Offset(30 * scale, 23 * scale),
      Offset(70 * scale, 23 * scale),
      Offset(22 * scale, 42 * scale),
      Offset(50 * scale, 38 * scale),
      Offset(78 * scale, 42 * scale),
    ];
    final links = <List<int>>[
      [0, 1],
      [0, 2],
      [1, 3],
      [1, 4],
      [2, 4],
      [2, 5],
      [3, 4],
      [4, 5],
    ];
    for (final link in links) {
      canvas.drawLine(nodes[link[0]], nodes[link[1]], networkPaint);
    }

    for (var index = 0; index < nodes.length; index++) {
      final nodePaint = Paint()
        ..color = index == 2 || index == 5 ? AppColors.teal : AppColors.primary;
      canvas.drawCircle(nodes[index], 4 * scale, nodePaint);
      canvas.drawCircle(
        nodes[index],
        6 * scale,
        Paint()
          ..color = nodePaint.color.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PromptWiseLogoPainter oldDelegate) {
    return oldDelegate.darkMode != darkMode;
  }
}
