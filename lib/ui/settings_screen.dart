import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/telecom_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterTts _tts = FlutterTts();
  List<Map<String, String>> _voices = [];
  Map<String, String>? _selectedVoice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initVoices();
  }

  Future<void> _initVoices() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('tts_voice_name');
    final savedLocale = prefs.getString('tts_voice_locale');

    final dynamic voicesDynamic = await _tts.getVoices;
    final List<Map<String, String>> englishVoices = [];

    if (voicesDynamic != null) {
      for (final voice in voicesDynamic) {
        final name = voice['name'] as String?;
        final locale = voice['locale'] as String?;
        // Filter for English voices to keep the list clean and relevant.
        if (name != null &&
            locale != null &&
            locale.toLowerCase().startsWith('en')) {
          englishVoices.add({'name': name, 'locale': locale});
        }
      }
    }

    // Sort alphabetically by locale, then name.
    englishVoices.sort((a, b) {
      final localeComparison = a['locale']!.compareTo(b['locale']!);
      if (localeComparison != 0) return localeComparison;
      return a['name']!.compareTo(b['name']!);
    });

    Map<String, String>? currentVoice;
    if (savedName != null && savedLocale != null) {
      currentVoice = englishVoices
          .where(
            (voice) =>
                voice['name'] == savedName && voice['locale'] == savedLocale,
          )
          .firstOrNull;
    }

    if (!mounted) return;
    setState(() {
      _voices = englishVoices;
      _selectedVoice = currentVoice;
      _isLoading = false;
    });
  }

  Future<void> _selectVoice(Map<String, String> voice) async {
    setState(() => _selectedVoice = voice);

    // Save to SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice_name', voice['name']!);
    await prefs.setString('tts_voice_locale', voice['locale']!);

    // Preview the voice.
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    await _tts.setSpeechRate(0.5);
    await _tts.speak('Carpe Diem. This is how I will sound.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: Text(
          'Assistant Voice',
          style: GoogleFonts.outfit(
            color: AppColors.text,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Select your preferred assistant voice. Only voices currently downloaded on your device are shown.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _voices.length,
                    itemBuilder: (context, index) {
                      final voice = _voices[index];
                      final isSelected = _selectedVoice?['name'] == voice['name'];
                      return ListTile(
                        title: Text(
                          voice['name'] ?? 'Unknown',
                          style: GoogleFonts.inter(
                            color: AppColors.text,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          voice['locale'] ?? '',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                              )
                            : null,
                        tileColor: isSelected
                            ? AppColors.surfaceElevated
                            : Colors.transparent,
                        onTap: () => _selectVoice(voice),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: TelecomService.openTTSSettings,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download More Voices'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.accent,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
