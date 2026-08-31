import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'ui/dashboard_screen.dart';
import 'ui/permissions_firewall.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await NotificationService.showPersistentInputNotification();

  final prefs = await SharedPreferences.getInstance();
  final bool setupDone = prefs.getBool('firewall_setup_completed') ?? false;

  runApp(CarpeDiemApp(startAtDashboard: setupDone));
}

class CarpeDiemApp extends StatelessWidget {
  final bool startAtDashboard;
  const CarpeDiemApp({super.key, required this.startAtDashboard});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carpe Diem',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
      ),
      home: startAtDashboard ? const DashboardScreen() : const PermissionsFirewall(),
      debugShowCheckedModeBanner: false,
    );
  }
}
