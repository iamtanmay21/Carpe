import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/theme.dart';
import '../services/telecom_service.dart';
import 'dashboard_screen.dart';

class PermissionsFirewall extends StatefulWidget {
  const PermissionsFirewall({super.key});

  @override
  State<PermissionsFirewall> createState() => _PermissionsFirewallState();
}

class _PermissionsFirewallState extends State<PermissionsFirewall> with WidgetsBindingObserver {
  bool _micGranted = false;
  bool _contactsGranted = false;
  bool _alarmsGranted = false;
  bool _notificationGranted = false;
  bool _telecomEnabled = false;
  bool _batteryBypassGranted = false;
  
  // New Engine States
  bool _ttsAvailable = false;
  bool _sttAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _micGranted = true;
          _contactsGranted = true;
          _alarmsGranted = true;
          _notificationGranted = true;
          _telecomEnabled = true;
          _batteryBypassGranted = true;
          _ttsAvailable = true;
          _sttAvailable = true;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('firewall_setup_completed', true);
        _completeSetup();
      }
      return;
    }

    final mic = await Permission.microphone.isGranted;
    final contacts = await Permission.contacts.isGranted;
    final alarms = await Permission.scheduleExactAlarm.isGranted;
    final notification = await Permission.notification.isGranted;
    final telecom = await TelecomService.isPhoneAccountEnabled();
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;

    // Check TTS Engine
    final tts = FlutterTts();
    final engines = await tts.getEngines;
    final hasTTS = engines != null && engines.isNotEmpty;

    // Check STT Engine (Only checks if Mic is granted to avoid premature prompts)
    bool hasSTT = false;
    if (mic) {
      final stt = SpeechToText();
      hasSTT = await stt.initialize(onError: (_) {}, onStatus: (_) {});
    }

    if (mounted) {
      setState(() {
        _micGranted = mic;
        _contactsGranted = contacts;
        _alarmsGranted = alarms;
        _notificationGranted = notification;
        _telecomEnabled = telecom;
        _batteryBypassGranted = battery;
        _ttsAvailable = hasTTS;
        _sttAvailable = hasSTT;
      });

      if (_allClear) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('firewall_setup_completed', true);
      }
    }
  }

  bool get _allClear => 
    _micGranted && _contactsGranted && _alarmsGranted && 
    _notificationGranted &&
    _telecomEnabled && _batteryBypassGranted && 
    _ttsAvailable && _sttAvailable;

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firewall_setup_completed', true);
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System Setup', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.text)),
              const SizedBox(height: 8),
              Text('Grant the following permissions and engines so Carpe Diem can ring and speak natively.', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 24),

              Expanded(
                child: ListView(
                  children: [
                    _buildRow('Microphone & Contacts', _micGranted && _contactsGranted, () async {
                      await [Permission.microphone, Permission.contacts].request();
                      _checkPermissions();
                    }),
                    
                    _buildRow('Exact Alarms (Wake Lock)', _alarmsGranted, () async {
                      await Permission.scheduleExactAlarm.request();
                      _checkPermissions();
                    }),

                    _buildRow(
                      'Notifications',
                      _notificationGranted,
                      () async {
                        await Permission.notification.request();
                        _checkPermissions();
                      },
                      icon: Icons.notifications_active_outlined,
                      subtitle: 'Required for persistent assistant and task reminders.',
                    ),
                    
                    _buildRow('Telecom Calling Account', _telecomEnabled, TelecomService.openTelecomSettings, subtitle: 'Enable "Carpe Diem" switch in Calling Accounts'),
                    
                    _buildRow('Disable Battery Restrictions', _batteryBypassGranted, () async {
                      await Permission.ignoreBatteryOptimizations.request();
                      _checkPermissions();
                    }, subtitle: 'Required so MIUI doesn\'t kill your alarms.'),

                    // Voice Engines Check
                    _buildRow('Speech-to-Text Engine', _sttAvailable, TelecomService.openPlayStoreForSpeechServices, subtitle: 'Required for voice transcriptions. Install Google Speech Services.'),
                    _buildRow('Text-to-Speech Engine', _ttsAvailable, TelecomService.openTTSSettings, subtitle: 'Required to read tasks aloud during a call.'),

                    // OEM Custom Autostart Bypass
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.rocket_launch_rounded, color: AppColors.warning, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enable Autostart (MIUI/Oppo)', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                                Text('Required for alarms to survive phone reboots.', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: TelecomService.openAutoStartSettings,
                            child: Text('OPEN', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.accent)),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allClear ? AppColors.accent : AppColors.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _allClear ? _completeSetup : null,
                  child: Text('Get Started', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _allClear ? Colors.white : AppColors.textMuted)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    String title,
    bool isMet,
    VoidCallback onFix, {
    IconData? icon,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMet ? AppColors.success.withAlpha(50) : AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            icon ??
                (isMet
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked),
            color: isMet ? AppColors.success : AppColors.textMuted,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (subtitle != null) Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (!isMet)
            TextButton(
              onPressed: onFix,
              child: Text('FIX', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.error)),
            )
        ],
      ),
    );
  }
}
