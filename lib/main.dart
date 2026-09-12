import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'services/assistant_executor.dart';
import 'services/database_helper.dart';
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

@pragma('vm:entry-point')
Future<void> quickCaptureHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel('com.local.carpe/quick_capture_worker');

  try {
    await NotificationService.initialize(isHeadless: true);
    final db = await DatabaseHelper.instance.database;

    final pending = await db.query(
      'capture_inbox',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
    );

    for (final capture in pending) {
      final id = capture['id'];
      final text = capture['raw_text'] as String;
      final timestamp = capture['created_at'] as int;

      final refDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final result = await AssistantExecutor.instance.executeVoiceCommand(
        text,
        referenceDate: refDate,
      );

      await db.update(
        'capture_inbox',
        {'status': 'DONE'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await NotificationService.showAssistantFeedback(result);
    }
    await channel.invokeMethod<void>('success');
  } catch (e) {
    await NotificationService.showIsolateCrash('Headless Crash: $e');
    await channel.invokeMethod<void>('retry');
  }
}
