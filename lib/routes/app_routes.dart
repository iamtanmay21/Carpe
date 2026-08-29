import 'package:go_router/go_router.dart';
import '../ui/dashboard_screen.dart';

class AppRoutes {
  // TODO: Add your routes here
  static const String initial = '/'; // 🚨 CRITICAL: DO NOT REMOVE THIS ROUTE
}

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: AppRoutes.initial,
      builder: (context, state) => const DashboardScreen(),
    ),
  ],
);
