import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const indigo900 = Color(0xFF1E1B4B);
  static const indigo700 = Color(0xFF3730A3);
  static const primary = Color(0xFF4F46E5);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const slate900 = Color(0xFF0F172A);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate100 = Color(0xFFF1F5F9);
  static const surface = Color(0xFFF8FAFC);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double page = 24;
}

class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standardCurve = Curves.easeOutCubic;
}

class AppBreakpoints {
  AppBreakpoints._();

  // Width-based classes keep the same layout behavior on Android, iOS,
  // tablets, foldables, and resizable web windows.
  static const double compact = 600;
  static const double tablet = 840;
  static const double desktop = 1200;
  static const double contentMaxWidth = 1280;
  static const double readingMaxWidth = 820;
}

class AppStrings {
  AppStrings._();

  static const appName = 'PromptWise';
  static const tagline = 'Learn AI wisely';
  static const welcomeTitle =
      'Build the skills to use AI responsibly, effectively, and with confidence.';
  static const welcomeButton = 'Get Started';
}

class AppIcons {
  AppIcons._();

  static IconData module(String token) {
    switch (token) {
      case 'prompt':
        return Icons.edit_note_rounded;
      case 'ethics':
        return Icons.verified_user_outlined;
      case 'privacy':
        return Icons.lock_outline_rounded;
      case 'bias':
        return Icons.balance_outlined;
      case 'media':
        return Icons.image_search_outlined;
      case 'verify':
        return Icons.image_search_outlined;
      case 'scam':
        return Icons.gpp_maybe_outlined;
      case 'trends':
        return Icons.trending_up_rounded;
      case 'ai':
      default:
        return Icons.psychology_alt_outlined;
    }
  }
}

/// Stable badge IDs are stored instead of display labels so presentation
/// changes do not invalidate previously earned badges.
class ProgressBadges {
  ProgressBadges._();

  static const aiExplorer = 'ai_explorer';
  static const promptImprover = 'prompt_improver';
  static const aiDetective = 'ai_detective';
  static const quizAce = 'quiz_ace';

  static const values = <String>{
    aiExplorer,
    promptImprover,
    aiDetective,
    quizAce,
  };

  static String? normalize(String storedValue) {
    final value = storedValue.trim();
    if (values.contains(value)) return value;

    switch (value) {
      case '\u{1F3C6} AI Explorer':
        return aiExplorer;
      case '\u{270D}\u{FE0F} Prompt Improver':
        return promptImprover;
      case '\u{1F575}\u{FE0F} AI Detective':
        return aiDetective;
      case '\u{26A1} Quiz Ace':
      case '\u{1F3C6} Quiz Ace':
      case 'Quiz Ace ':
        return quizAce;
      default:
        return null;
    }
  }
}
