import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/onboarding_controller.dart';

/// First-login orientation. Reopen from Profile without resetting progress.
class OnboardingOrientationScreen extends StatefulWidget {
  final bool replay;

  const OnboardingOrientationScreen({super.key, this.replay = false});

  @override
  State<OnboardingOrientationScreen> createState() =>
      _OnboardingOrientationScreenState();
}

class _OnboardingOrientationScreenState extends State<OnboardingOrientationScreen> {
  late final VideoPlayerController _player;
  bool _ready = false;
  bool _videoError = false;
  bool _watchedToEnd = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.asset(
      'assets/videos/promptwise_awareness.mp4',
    );
    _player.addListener(_onVideoChanged);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await _player.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoError = true);
    }
  }

  void _onVideoChanged() {
    if (!mounted) return;
    final value = _player.value;
    final watched = _watchedToEnd || value.isCompleted;
    if (watched != _watchedToEnd || value.isPlaying != _isPlaying) {
      setState(() {
        _watchedToEnd = watched;
        _isPlaying = value.isPlaying;
      });
    }
    if (value.hasError && !_videoError) {
      setState(() => _videoError = true);
    }
  }

  Future<void> _togglePlayback() async {
    if (!_ready || _videoError) return;
    try {
      if (_player.value.isPlaying) {
        await _player.pause();
      } else {
        if (_player.value.isCompleted) await _player.seekTo(Duration.zero);
        await _player.play();
      }
    } catch (_) {
      if (mounted) setState(() => _videoError = true);
    }
  }

  Future<void> _continue() async {
    final controller = context.read<OnboardingController>();
    final saved = await controller.completeOrientation(watched: _watchedToEnd);
    if (!mounted || !saved) return;
    if (widget.replay) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.root,
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onVideoChanged);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OnboardingController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.replay,
        title: const Text('Welcome to PromptWise'),
        actions: [
          if (!widget.replay)
            TextButton(
              onPressed: () => context.read<AuthController>().signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              children: [
                Text(
                  'Discover what you can do',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'An introduction to learning, practicing, and verifying '
                  'AI-generated information. Video: 58 seconds, on-screen '
                  'captions and background music.',
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: const Color(0xFF0B1027),
                      child: _ready && !_videoError
                          ? VideoPlayer(_player)
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _videoError
                                    ? const Text(
                                        'Video unavailable. Read the full '
                                        'transcript below to continue.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white),
                                      )
                                    : const CircularProgressIndicator(),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_ready && !_videoError) ...[
                  VideoProgressIndicator(
                    _player,
                    allowScrubbing: false,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                      label: Text(_isPlaying ? 'Pause video' : 'Play video'),
                    ),
                  ),
                ],
                if (_watchedToEnd || controller.videoWatched)
                  const Text('Video watched'),
                const SizedBox(height: 16),
                const _BenefitRow(
                  icon: Icons.menu_book_outlined,
                  title: 'Learn',
                  description: 'Explore prompt clarity, context, specificity, '
                      'responsible AI use, and verification.',
                ),
                const _BenefitRow(
                  icon: Icons.edit_note_outlined,
                  title: 'Practice',
                  description: 'Use knowledge checks to identify where you '
                      'might want more practice.',
                ),
                const _BenefitRow(
                  icon: Icons.fact_check_outlined,
                  title: 'Verify',
                  description: 'Review claims, sources, and the limitations '
                      'of AI-generated outputs.',
                ),
                const SizedBox(height: 6),
                const ExpansionTile(
                  title: Text('Video transcript (accessible alternative)'),
                  childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    SelectableText(
                      'AI can answer in seconds. But what if it gets it wrong? '
                      'A confident answer is not always a correct one. And a '
                      'vague prompt can lead to a confusing result.\n\n'
                      "That's why we created PromptWise: a learning platform "
                      'for smarter, more responsible AI use. Learn how to write '
                      'clearer prompts and explore practical lessons. Then test '
                      'your understanding with Knowledge Checks.\n\n'
                      'Discover AI-related risks in the Awareness Feed, and use '
                      'Verification Studio to examine information more carefully '
                      'before believing or sharing it. Because using AI well '
                      'means knowing when to question its answers.\n\n'
                      'Prompt better. Think critically. Verify first. '
                      'Welcome to PromptWise.',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (controller.errorMessage != null) ...[
                  Text(
                    controller.errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: controller.isSaving ? null : _continue,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      controller.isSaving
                          ? 'Saving orientation...'
                          : widget.replay
                              ? 'Done'
                              : _watchedToEnd
                                  ? 'Continue to PromptWise'
                                  : 'Continue (watch later)',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Watching the full video is optional. You can replay it '
                  'from Profile. Continuing does not mark it as watched.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
