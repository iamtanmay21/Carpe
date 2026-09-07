import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'ui/dashboard_screen.dart';
import 'ui/permissions_firewall.dart';
import 'services/notification_service.dart';
import 'services/assistant_executor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await const MethodChannel('com.local.carpe/overlay')
      .invokeMethod<void>('showPersistentNotification');

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
      routes: {
        '/quick_capture': (context) => const QuickCaptureOverlay(),
      },
      home: startAtDashboard ? const DashboardScreen() : const PermissionsFirewall(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class QuickCaptureOverlay extends StatefulWidget {
  const QuickCaptureOverlay({super.key});

  @override
  State<QuickCaptureOverlay> createState() => _QuickCaptureOverlayState();
}

class _QuickCaptureOverlayState extends State<QuickCaptureOverlay> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          _focusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    if (text.trim().isNotEmpty) {
      await AssistantExecutor.instance.executeVoiceCommand(text.trim());
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'e.g. Call mom at 7:30',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
