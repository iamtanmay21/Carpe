import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import 'session_manager.dart';

class VoiceInputController extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  
  bool _isInitialized = false;
  bool _isListening = false;
  String _currentTranscript = '';
  String _finalizedTranscript = '';
  double _soundLevel = 0.0;
  
  bool get isListening => _isListening;
  String get currentTranscript => _currentTranscript;
  String get finalizedTranscript => _finalizedTranscript;
  double get soundLevel => _soundLevel;

  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    _isInitialized = await _speechToText.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    return _isInitialized;
  }

  /// Initiates a standard long-session listening window (up to 30 seconds).
  Future<void> startListening() async {
    if (!_isInitialized) {
      bool ready = await initSpeech();
      if (!ready) return;
    }

    _resetState();
    _isListening = true;
    notifyListeners();

    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4), // Expand silence tolerance
      partialResults: true,
      onSoundLevelChange: _onSoundLevelChange,
      cancelOnError: false,
      listenMode: ListenMode.dictation, // Prevents aggressive OS auto-shutoff
    );
  }

  /// Initiates a shorter, targeted session when awaiting user clarification.
  Future<void> listenForClarification() async {
    if (!_isInitialized) {
      bool ready = await initSpeech();
      if (!ready) return;
    }

    _resetState();
    _isListening = true;
    notifyListeners();

    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 15), // Shorter window for short answers
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onSoundLevelChange: _onSoundLevelChange,
      cancelOnError: false,
      listenMode: ListenMode.confirmation,
    );
  }

  /// Manually stops the microphone and finalizes the transcript for execution.
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    await _speechToText.stop();
    _soundLevel = 0.0;
    
    // Fallback: If no final result was emitted but we have partials, lock it in.
    if (_finalizedTranscript.isEmpty && _currentTranscript.isNotEmpty) {
      _finalizedTranscript = _currentTranscript;
    }
    
    notifyListeners();
  }

  /// Aborts the session entirely, discarding all transcripts.
  Future<void> cancelListening() async {
    if (!_isListening) return;

    await _speechToText.cancel();
    _isListening = false;
    _soundLevel = 0.0;
    _currentTranscript = '';
    _finalizedTranscript = '';
    
    // If we aborted while in a clarification loop, clear the session state.
    if (SessionManager.instance.hasActiveSession) {
      SessionManager.instance.clearSession();
    }
    
    notifyListeners();
  }

  /// Safely wipes the transcript memory to prevent duplicate firing
  void clearTranscript() {
    _currentTranscript = '';
    _finalizedTranscript = '';
    notifyListeners();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!_isListening) return;

    _currentTranscript = result.recognizedWords;
    if (result.finalResult) {
      _finalizedTranscript = result.recognizedWords;
    }
    notifyListeners();
  }

  void _onSoundLevelChange(double level) {
    _soundLevel = level;
    notifyListeners();
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      // The OS ended the session automatically
      if (_isListening) {
        _isListening = false;
        _soundLevel = 0.0;
        
        if (_finalizedTranscript.isEmpty && _currentTranscript.isNotEmpty) {
          _finalizedTranscript = _currentTranscript;
        }

        // If we were waiting for clarification and got nothing, clear the session.
        if (_finalizedTranscript.isEmpty && SessionManager.instance.hasActiveSession) {
          SessionManager.instance.clearSession();
        }
        
        notifyListeners();
      }
    }
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('Speech-to-Text Error: ${error.errorMsg}');
    
    // Handle specific recoverable errors gracefully
    if (error.errorMsg == 'error_speech_timeout' || error.errorMsg == 'error_no_match') {
      if (_isListening) {
        stopListening(); // Gracefully stop instead of crashing
      }
    } else {
      // Permission or hardware errors
      _isListening = false;
      _soundLevel = 0.0;
      notifyListeners();
    }
  }

  void _resetState() {
    _currentTranscript = '';
    _finalizedTranscript = '';
    _soundLevel = 0.0;
  }
}
