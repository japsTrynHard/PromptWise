import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/auth_otp_request.dart';
import '../../data/models/awareness_filter.dart';
import '../../data/models/lesson.dart';
import '../../data/models/quiz.dart';
import '../utils/constants.dart';
import '../../presentation/screens/user/adaptive_knowledge_check_screen.dart';
import '../../presentation/screens/user/adaptive_learning_screen.dart';
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/auth/auth_gate_screen.dart';
import '../../presentation/screens/auth/forgot_password_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/auth/reset_password_screen.dart';
import '../../presentation/screens/auth/signup_confirmation_screen.dart';
import '../../presentation/screens/auth/verify_email_screen.dart';
import '../../presentation/screens/user/dashboard_screen.dart';
import '../../presentation/screens/user/diagnostic_assessment_screen.dart';
import '../../presentation/screens/user/image_compare_screen.dart';
import '../../presentation/screens/user/lesson_detail_screen.dart';
import '../../presentation/screens/user/module_list_screen.dart';
import '../../presentation/screens/user/news_screen.dart';
import '../../presentation/screens/user/quiz_screen.dart';
import '../../presentation/screens/user/sandbox_screen.dart';
import '../../presentation/screens/shared/welcome_screen.dart';
import '../../presentation/screens/user/verification_session_screen.dart';
import '../../presentation/widgets/state_message.dart';

class AppRoutes {
  AppRoutes._();

  static const String root = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String confirmEmail = '/confirm-email';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String dashboard = '/dashboard';
  static const String module = '/module';
  static const String lesson = '/lesson';
  static const String quiz = '/quiz';
  static const String sandbox = '/sandbox';
  static const String imageCompare = '/compare-images';
  static const String game = '/real-or-ai'; // Backward-compatible old link.
  static const String awareness = '/awareness';
  static const String adaptiveLearning = '/adaptive-learning';
  static const String adaptiveKnowledgeCheck = '/adaptive-knowledge-check';
  static const String diagnostic = '/diagnostic';
  static const String verificationSession = '/verification-session';
  static const String admin = '/admin';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case root:
        return _page(settings, const AuthGateScreen(), fadeOnly: true);
      case welcome:
        return _page(settings, const WelcomeScreen(), fadeOnly: true);
      case login:
        return _page(settings, const LoginScreen());
      case register:
        return _page(settings, const RegisterScreen());
      case confirmEmail:
        final value = settings.arguments;
        return _page(
          settings,
          SignupConfirmationScreen(email: value is String ? value : ''),
        );
      case verifyEmail:
        final value = settings.arguments;
        return _page(
          settings,
          VerifyEmailScreen(request: value is AuthOtpRequest ? value : null),
        );
      case forgotPassword:
        return _page(settings, const ForgotPasswordScreen());
      case resetPassword:
        return _page(settings, const ResetPasswordScreen());
      case dashboard:
        return _page(
          settings,
          const AuthenticatedRoute(child: DashboardScreen()),
          fadeOnly: true,
        );
      case sandbox:
        return _page(
          settings,
          const AuthenticatedRoute(child: SandboxScreen()),
        );
      case imageCompare:
      case game:
        return _page(settings, const AuthenticatedRoute(child: ImageCompareScreen()));
      case awareness:
        final value = settings.arguments;
        return _page(
          settings,
          AuthenticatedRoute(
            child: NewsScreen(filter: value is AwarenessFilter ? value : null),
          ),
        );
      case adaptiveLearning:
        return _page(
          settings,
          const AuthenticatedRoute(child: AdaptiveLearningScreen()),
        );
      case adaptiveKnowledgeCheck:
        final value = settings.arguments;
        return _page(
          settings,
          AuthenticatedRoute(
            child: AdaptiveKnowledgeCheckScreen(
              args: value is AdaptiveKnowledgeCheckArgs
                  ? value
                  : const AdaptiveKnowledgeCheckArgs(),
            ),
          ),
        );
      case diagnostic:
        return _page(
          settings,
          const AuthenticatedRoute(child: DiagnosticAssessmentScreen()),
        );
      case verificationSession:
        return _page(
          settings,
          const AuthenticatedRoute(child: VerificationSessionScreen()),
        );
      case admin:
        return _page(
          settings,
          const AdministratorRoute(child: AdminDashboardScreen()),
          fadeOnly: true,
        );
      case module:
        final value = settings.arguments;
        if (value is Module) {
          return _page(
            settings,
            AuthenticatedRoute(child: ModuleListScreen(module: value)),
          );
        }
        return _invalidArgumentsRoute(settings, 'learning module');
      case lesson:
        final value = settings.arguments;
        if (value is Lesson) {
          return _page(
            settings,
            AuthenticatedRoute(child: LessonDetailScreen(lesson: value)),
          );
        }
        return _invalidArgumentsRoute(settings, 'lesson');
      case quiz:
        final value = settings.arguments;
        if (value is Quiz) {
          return _page(
            settings,
            AuthenticatedRoute(child: QuizScreen(quiz: value)),
          );
        }
        return _invalidArgumentsRoute(settings, 'quiz');
      default:
        return _page(
          settings,
          const _RouteErrorScreen(
            title: 'Page not found',
            message: 'The requested page is unavailable.',
          ),
        );
    }
  }

  static Route<dynamic> _page(
    RouteSettings settings,
    Widget child, {
    bool fadeOnly = false,
  }) {
    if (fadeOnly) {
      return PageRouteBuilder<dynamic>(
        settings: settings,
        transitionDuration: AppMotion.fast,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder:
            (context, animation, secondaryAnimation, routeChild) {
          if (!AppMotion.animationsEnabled(context)) return routeChild;
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.standardCurve,
            reverseCurve: AppMotion.reverseCurve,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: routeChild,
          );
        },
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Native iOS push/pop motion also restores the familiar edge-swipe back
      // gesture instead of making every detail page feel like a custom demo.
      return CupertinoPageRoute<dynamic>(
        settings: settings,
        builder: (_) => child,
      );
    }

    final desktopPlatform = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (kIsWeb || desktopPlatform) {
      return PageRouteBuilder<dynamic>(
        settings: settings,
        transitionDuration: AppMotion.fast,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder:
            (context, animation, secondaryAnimation, routeChild) {
          if (!AppMotion.animationsEnabled(context)) return routeChild;
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.standardCurve,
            reverseCurve: AppMotion.reverseCurve,
          );
          final fade = Tween<double>(begin: 0.95, end: 1).animate(curved);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.008),
            end: Offset.zero,
          ).animate(curved);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: routeChild),
          );
        },
      );
    }

    // Android uses a short Material-style forward motion: mostly fade with a
    // very small vertical offset so navigation feels immediate rather than
    // like a full-screen carousel.
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: AppMotion.normal,
      reverseTransitionDuration: AppMotion.normal,
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder:
          (context, animation, secondaryAnimation, routeChild) {
        if (!AppMotion.animationsEnabled(context)) return routeChild;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.standardCurve,
          reverseCurve: AppMotion.reverseCurve,
        );
        final fade = Tween<double>(begin: 0.93, end: 1).animate(curved);
        final slide = Tween<Offset>(
          begin: const Offset(0.012, 0.010),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: routeChild),
        );
      },
    );
  }

  static Route<dynamic> _invalidArgumentsRoute(
    RouteSettings settings,
    String pageName,
  ) {
    return _page(
      settings,
      _RouteErrorScreen(
        title: 'Unable to open $pageName',
        message: 'Required page information was missing or invalid.',
      ),
    );
  }
}

class _RouteErrorScreen extends StatelessWidget {
  final String title;
  final String message;

  const _RouteErrorScreen({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PromptWise')),
      body: StateMessage.error(
        title: title,
        message: message,
        actionLabel: 'Go back',
        onAction: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.root);
          }
        },
      ),
    );
  }
}
