import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/assistant_executor.dart';
import '../core/theme.dart';
import 'dashboard_screen.dart'; // To access the manual view

class VoiceHomeScreen extends StatefulWidget {
  const VoiceHomeScreen({super.key});

  @override
  State<VoiceHomeScreen> createState() => _VoiceHomeScreenState();
}

class _VoiceHomeScreenState extends State<VoiceHomeScreen> {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _transcript = "";
  String _assistantResponse = "Tap the mic and speak.";

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speech.initialize(
        onStatus: (status) async {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
            // Process the text when speech stops
            if (_transcript.isNotEmpty) {
              setState(() => _assistantResponse = "Processing...");
              final result = await AssistantExecutor.instance.executeVoiceCommand(_transcript);
              String response = result.feedbackMessage;
              setState(() => _assistantResponse = response);
            }
          }
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
          _transcript = "";
          _assistantResponse = "Listening...";
        });
        await _speech.listen(onResult: (result) {
          setState(() => _transcript = result.recognizedWords);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Carpe Diem AI'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('You said:', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('"$_transcript"', style: const TextStyle(fontSize: 20, color: Colors.white, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            Text('Assistant:', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(_assistantResponse, style: const TextStyle(fontSize: 18, color: AppColors.accent), textAlign: TextAlign.center),
            const SizedBox(height: 80),
            FloatingActionButton.large(
              onPressed: _toggleMic,
              backgroundColor: _isListening ? Colors.red : AppColors.accent,
              child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
            ),
          ],
        ),
      ),
    );
  }
}
