import 'package:flutter/material.dart';

import '../views/screens/dashboard_screen.dart';
import '../views/screens/welcome_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String welcome = '/';
  static const String dashboard = '/dashboard';

  static Map<String, WidgetBuilder> get routes => {
        welcome: (_) => const WelcomeScreen(),
        dashboard: (_) => const DashboardScreen(),
      };
}
