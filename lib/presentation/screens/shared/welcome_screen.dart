import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/fade_slide_in.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF07111F), Color(0xFF111B35)]
                      : const [Color(0xFFF8FAFF), Color(0xFFEEF2FF)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _GlowOrb(
              size: 260,
              color: AppColors.violet.withValues(alpha: isDark ? 0.16 : 0.12),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: _GlowOrb(
              size: 300,
              color: AppColors.teal.withValues(alpha: isDark ? 0.13 : 0.10),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                final content = _WelcomeContent(wide: wide);

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(
                      AdaptiveLayout.horizontalPaddingFor(constraints.maxWidth),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 6, child: content),
                                const SizedBox(width: 56),
                                const Expanded(flex: 5, child: _PurposePanel()),
                              ],
                            )
                          : content,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  final bool wide;

  const _WelcomeContent({required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        FadeSlideIn(
          child: AppLogo(
            size: wide ? 78 : 68,
            showTagline: true,
            alignment: wide
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
          ),
        ),
        const SizedBox(height: 44),
        FadeSlideIn(
          order: 1,
          child: Text(
            AppStrings.welcomeTitle,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: wide ? 46 : 34,
              height: 1.12,
            ),
            textAlign: wide ? TextAlign.left : TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FadeSlideIn(
          order: 2,
          child: Text(
            'PromptWise helps you understand AI, improve your own prompts, and recognize AI-generated or manipulated content more carefully.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: wide ? TextAlign.left : TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        FadeSlideIn(
          order: 3,
          child: Wrap(
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: const [
              _PurposeChip(
                icon: Icons.menu_book_outlined,
                label: 'Learn AI clearly',
              ),
              _PurposeChip(
                icon: Icons.edit_note_rounded,
                label: 'Practice responsibly',
              ),
              _PurposeChip(
                icon: Icons.image_search_outlined,
                label: 'Recognize AI content',
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        FadeSlideIn(
          order: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.register),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(AppStrings.welcomeButton),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.login),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Sign in to PromptWise'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FadeSlideIn(
          order: 5,
          child: Text(
            'Create an account to keep your learning progress connected across your devices.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: wide ? TextAlign.left : TextAlign.center,
          ),
        ),
        if (!wide) ...[
          const SizedBox(height: 36),
          const FadeSlideIn(order: 6, child: _PurposePanel()),
        ],
      ],
    );
  }
}

class _PurposePanel extends StatelessWidget {
  const _PurposePanel();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              Icons.route_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'A clear path from learning to responsible action',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _PurposeStep(
            number: '1',
            title: 'Learn',
            description: 'Build AI literacy through short, focused modules.',
          ),
          const _PurposeStep(
            number: '2',
            title: 'Practice',
            description:
                'Improve your own prompts with guidance, not automatic rewriting.',
          ),
          const _PurposeStep(
            number: '3',
            title: 'Verify',
            description:
                'Practice spotting AI-generated or manipulated media and review safe AI-use guidance.',
          ),
        ],
      ),
    );
  }
}

class _PurposeStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _PurposeStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              number,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurposeChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PurposeChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(label),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
