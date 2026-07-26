import 'package:flutter/material.dart';

class BadgeWidget extends StatelessWidget {
  final String emoji;
  final String label;
  final bool earned;

  const BadgeWidget({
    super.key,
    required this.emoji,
    required this.label,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: earned
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade200,
          child: Text(
            emoji,
            style: TextStyle(fontSize: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
