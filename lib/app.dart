import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import './presentation/controllers/auth_controller.dart';
import './presentation/controllers/theme_controller.dart';
import './core/routes/app_routes.dart';
import './core/routes/auth_callback_url.dart';
import './core/theme/app_theme.dart';
import './core/utils/constants.dart';

class PromptWiseApp extends StatefulWidget {
  const PromptWiseApp({super.key});

  @override
  State<PromptWiseApp> createState() => _PromptWiseAppState();
}

class _PromptWiseAppState extends State<PromptWiseApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final String _initialRoute;
  bool _recoveryRouteScheduled = false;
  String? _scheduledLinkError;

  @override
  void initState() {
    super.initState();
    final uri = Uri.base;
    _initialRoute = AppRoutes.initialRouteForUri(uri);
    clearFailedAuthCallbackUrl(uri);
  }

  void _syncAuthLinkError(String? message) {
    if (message == null) {
      _scheduledLinkError = null;
      return;
    }
    if (_scheduledLinkError == message) return;
    _scheduledLinkError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          context.read<AuthController>().authLinkErrorMessage != message) {
        return;
      }
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.forgotPassword,
        (_) => false,
        arguments: message,
      );
    });
  }

  void _syncPasswordRecoveryRoute(bool isPasswordRecovery) {
    if (!isPasswordRecovery) {
      _recoveryRouteScheduled = false;
      return;
    }
    if (_recoveryRouteScheduled) return;
    _recoveryRouteScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.read<AuthController>().isPasswordRecovery) {
        _recoveryRouteScheduled = false;
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _recoveryRouteScheduled = false;
        return;
      }
      navigator
          .pushNamedAndRemoveUntil(AppRoutes.resetPassword, (_) => false)
          .whenComplete(() => _recoveryRouteScheduled = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().themeMode;
    final auth = context.watch<AuthController>();
    _syncPasswordRecoveryRoute(auth.isPasswordRecovery);
    _syncAuthLinkError(auth.authLinkErrorMessage);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: AppMotion.normal,
      themeAnimationCurve: AppMotion.standardCurve,
      initialRoute: _initialRoute,
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final disableAnimations =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;

        if (disableAnimations) {
          return content;
        }

        // Repaint isolation keeps theme and route animations from forcing
        // expensive repaints outside the active app surface.
        return RepaintBoundary(child: content);
      },
    );
  }
}
