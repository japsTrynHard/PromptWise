import 'package:flutter/material.dart';

import '../models/auth_otp_request.dart';
import '../models/awareness_filter.dart';
import '../models/lesson.dart';
import '../models/quiz.dart';
import '../utils/constants.dart';
import '../views/screens/admin_dashboard_screen.dart';
import '../views/screens/auth/auth_gate_screen.dart';
import '../views/screens/auth/forgot_password_screen.dart';
import '../views/screens/auth/login_screen.dart';
import '../views/screens/auth/register_screen.dart';
import '../views/screens/auth/reset_password_screen.dart';
import '../views/screens/auth/verify_email_screen.dart';
import '../views/screens/dashboard_screen.dart';
import '../views/screens/game_screen.dart';
import '../views/screens/lesson_detail_screen.dart';
import '../views/screens/module_list_screen.dart';
import '../views/screens/news_screen.dart';
import '../views/screens/quiz_screen.dart';
import '../views/screens/sandbox_screen.dart';
import '../views/screens/welcome_screen.dart';
import '../views/widgets/state_message.dart';

class AppRoutes {
  AppRoutes._();

  static const String root = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String dashboard = '/dashboard';
  static const String module = '/module';
  static const String lesson = '/lesson';
  static const String quiz = '/quiz';
  static const String sandbox = '/sandbox';
  static const String game = '/real-or-ai';
  static const String awareness = '/awareness';
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
      case game:
        return _page(settings, const AuthenticatedRoute(child: GameScreen()));
      case awareness:
        final value = settings.arguments;
        return _page(
          settings,
          AuthenticatedRoute(
            child: NewsScreen(filter: value is AwarenessFilter ? value : null),
          ),
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

  static PageRouteBuilder<dynamic> _page(
    RouteSettings settings,
    Widget child, {
    bool fadeOnly = false,
  }) {
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: AppMotion.normal,
      reverseTransitionDuration: AppMotion.fast,
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (_, animation, __, routeChild) {
        if (fadeOnly) {
          return FadeTransition(opacity: animation, child: routeChild);
        }
        final offsetAnimation =
            Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: AppMotion.standardCurve,
              ),
            );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: routeChild),
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
