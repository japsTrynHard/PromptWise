import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badge_widget.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/sync_status_banner.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progressController = context.watch<ProgressController>();
    final adaptive = context.watch<AdaptiveLearningController>();
    final auth = context.watch<AuthController>();
    final progress = progressController.progress;

    return AdaptiveBody(
      safeTop: false,
      safeBottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AdaptiveLayout.rootTabPageInsets(context),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const PageIntro(
                  eyebrow: 'You',
                  title: 'Your profile',
                  description:
                      'Review your account, progress, achievements, and appearance settings.',
                ),
                const SizedBox(height: AppSpacing.lg),
                const SyncStatusBanner(),
                const SizedBox(height: AppSpacing.xxl),
                _ProfileHeader(
                  name: auth.displayName,
                  email: auth.email,
                  role: auth.profile?.role.label ?? 'Learner',
                  level: progress.knowledgeLevel,
                  completed: progress.completedLessons,
                  total: progress.totalLessons,
                  quizScore: progressController.currentQuizScore,
                  maximumQuizScore: progressController.maximumQuizScore,
                ),
                const SizedBox(height: AppSpacing.section),
                Text(
                  'My learning path',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: _SettingsTile(
                    icon: Icons.route_outlined,
                    title: adaptive.diagnosticCompleted
                        ? 'Learning progress: ${adaptive.overallMastery}%'
                        : 'Set up your learning path',
                    subtitle: adaptive.diagnosticCompleted
                        ? '${adaptive.recommendationReason} Review topic progress and upcoming reviews.'
                        : 'Take the five-question starting check to get personalized recommendations.',
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.adaptiveLearning,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                Text('Account', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.edit_outlined,
                        title: 'Edit display name',
                        subtitle: auth.displayName,
                        onTap: auth.isLoading
                            ? null
                            : () => _editName(context, auth),
                      ),
                      if (kIsWeb && auth.isAdministrator) ...[
                        const Divider(height: 1),
                        _SettingsTile(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Open administrator workspace',
                          subtitle: 'Manage PromptWise from the web dashboard.',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.admin),
                        ),
                      ],
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign out',
                        subtitle:
                            'Your saved progress stays connected to this account.',
                        onTap: auth.isLoading
                            ? null
                            : () => _signOut(context, auth),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                Text(
                  'Achievements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    BadgeWidget(
                      icon: Icons.explore_outlined,
                      label: 'AI Explorer',
                      earned: progressController.hasBadge(
                        ProgressBadges.aiExplorer,
                      ),
                    ),
                    BadgeWidget(
                      icon: Icons.edit_note_rounded,
                      label: 'Prompt Improver',
                      earned: progressController.hasBadge(
                        ProgressBadges.promptImprover,
                      ),
                    ),
                    BadgeWidget(
                      icon: Icons.image_search_rounded,
                      label: 'AI Detective',
                      earned: progressController.hasBadge(
                        ProgressBadges.aiDetective,
                      ),
                    ),
                    BadgeWidget(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Quiz Ace',
                      earned: progressController.hasBadge(
                        ProgressBadges.quizAce,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                const _ThemeModeCard(),
                const SizedBox(height: AppSpacing.section),
                Text('Support', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy and data',
                        subtitle:
                            'Your learning progress is connected to your account and kept private from other learners.',
                        onTap: () => _showPrivacy(context),
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.help_outline_rounded,
                        title: 'Help and support',
                        subtitle: 'Review what every main section does.',
                        onTap: () => _showHelp(context),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, AuthController auth) async {
    final controller = TextEditingController(text: auth.displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 2) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    final success = await auth.updateFullName(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Profile updated.' : auth.errorMessage ?? 'Update failed.',
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, AuthController auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved progress will remain connected to this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final success = await auth.signOut();
    if (!context.mounted || !success) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
  }

  void _showPrivacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Privacy and data'),
        content: const Text(
          'Your learning progress belongs to your account. Other learners cannot view or change it, while authorized administrators have separate management access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Home: continue learning and view recommendations.\n\nLearn: browse modules, lessons, and look up unfamiliar terms.\n\nPractice: answer quizzes and improve your own prompts.\n\nVerify: compare images, answer short checks, and review online-safety guidance.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final String level;
  final int completed;
  final int total;
  final int quizScore;
  final int maximumQuizScore;

  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.role,
    required this.level,
    required this.completed,
    required this.total,
    required this.quizScore,
    required this.maximumQuizScore,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (completed / total).clamp(0, 1).toDouble();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.5,
          ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                child: Icon(Icons.person_rounded, size: 32),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(email, style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      '$role · $level knowledge level',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              color: AppColors.primary,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Stat(value: '$completed/$total', label: 'Lessons'),
              ),
              Expanded(
                child: _Stat(
                  value: '$quizScore/$maximumQuizScore',
                  label: 'Quiz points',
                ),
              ),
              Expanded(
                child: _Stat(
                  value: '${(ratio * 100).round()}%',
                  label: 'Completion',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Light is the default. You can also use Dark or follow your device setting.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              return SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: compact
                        ? null
                        : const Icon(Icons.brightness_auto_outlined),
                    label: const Text('Device'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: compact
                        ? null
                        : const Icon(Icons.light_mode_outlined),
                    label: const Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: compact ? null : const Icon(Icons.dark_mode_outlined),
                    label: const Text('Dark'),
                  ),
                ],
                selected: {controller.themeMode},
                showSelectedIcon: !compact,
                expandedInsets: EdgeInsets.zero,
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    controller.setThemeMode(selection.first);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
