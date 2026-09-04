import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/theme.dart';
import 'package:carpediem/services/database_helper.dart';
import '../data/models/task.dart';
import '../services/nlp_parser.dart';
import '../services/alarm_service.dart';

class CaptureSheet extends StatefulWidget {
  const CaptureSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CaptureSheet(),
    );
  }

  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<CaptureSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final SpeechToText _stt = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _sttAvailable = false;
  bool _isListening = false;
  bool _isRecordingVoiceNote = false;
  bool _isSaving = false;

  String? _recordedAudioPath;
  String? _contactName;
  String? _contactNumber;
  final List<String> _weekDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  final List<String> _selectedRoutineDays = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initStt();
  }

  Future<void> _initStt() async {
    try {
      _sttAvailable = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
              _pulseController.stop();
              _pulseController.reset();
            }
          }
        },
      );
    } catch (_) {
      _sttAvailable = false;
    }
  }

  Future<void> _toggleSpeechToText() async {
    if (!_sttAvailable) return;
    if (_isListening) {
      await _stt.stop();
      _pulseController.stop();
      _pulseController.reset();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      _pulseController.repeat(reverse: true);
      await _stt.listen(
        onResult: (result) {
          if (mounted) {
            setState(() => _textController.text = result.recognizedWords);
          }
        },
      );
    }
  }

  Future<void> _toggleVoiceNote() async {
    if (_isRecordingVoiceNote) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecordingVoiceNote = false;
        _recordedAudioPath = path;
      });
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = p.join(dir.path, 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        setState(() => _isRecordingVoiceNote = true);
      }
    }
  }

  Future<void> _pickContact() async {
    if (await FlutterContacts.requestPermission(readonly: true)) {
      final contact = await FlutterContacts.openExternalPick();
      if (contact != null) {
        final full = await FlutterContacts.getContact(contact.id);
        if (full != null && full.phones.isNotEmpty) {
          setState(() {
            _contactName = full.displayName;
            _contactNumber = full.phones.first.number;
          });
        }
      }
    }
  }

  Future<void> _saveTask() async {
    final raw = _textController.text.trim();
    if (raw.isEmpty && _recordedAudioPath == null) return;

    setState(() => _isSaving = true);

    try {
      final parsed = NlpParser.parseTranscript(raw.isEmpty ? "Voice Task" : raw);
      final dueMs = (parsed.dueDateTime ?? DateTime.now().add(const Duration(minutes: 5))).millisecondsSinceEpoch;

      final createdTask = Task.create(
        title: parsed.title,
        originalTranscript: raw,
        dueTimestamp: dueMs,
        audioPath: _recordedAudioPath,
        routineDays: _selectedRoutineDays,
        contactName: _contactName,
        contactNumber: _contactNumber,
      );

      await DatabaseHelper.instance.insertTask(createdTask);
      await AlarmService.instance.scheduleAlarm(createdTask);

      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrint('CRITICAL SAVE CRASH: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController.dispose();
    _stt.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
        border: Border(top: BorderSide(color: AppColors.surfaceElevated, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 44, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 16),
          Text('New Task', style: GoogleFonts.outfit(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),

          TextField(
            controller: _textController,
            autofocus: true,
            maxLines: 2,
            style: GoogleFonts.inter(color: AppColors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g., "Meeting tomorrow at 4pm"',
              hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 6,
            children: _weekDays.map((day) {
              final isSelected = _selectedRoutineDays.contains(day);
              return ChoiceChip(
                label: Text(day, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textSecondary)),
                selected: isSelected,
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.surfaceVariant,
                showCheckmark: false,
                onSelected: (selected) => setState(() {
                  selected ? _selectedRoutineDays.add(day) : _selectedRoutineDays.remove(day);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  ScaleTransition(
                    scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    child: IconButton.filledTonal(
                      onPressed: () { HapticFeedback.lightImpact(); _toggleSpeechToText(); },
                      style: IconButton.styleFrom(backgroundColor: _isListening ? AppColors.accent : AppColors.surfaceVariant),
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.white : AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () { HapticFeedback.lightImpact(); _toggleVoiceNote(); },
                    style: IconButton.styleFrom(backgroundColor: _isRecordingVoiceNote ? AppColors.error : (_recordedAudioPath != null ? AppColors.success.withAlpha(50) : AppColors.surfaceVariant)),
                    icon: Icon(Icons.graphic_eq, color: _isRecordingVoiceNote ? Colors.white : (_recordedAudioPath != null ? AppColors.success : AppColors.text)),
                    tooltip: 'Record Voice Note',
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () { HapticFeedback.lightImpact(); _pickContact(); },
                    style: IconButton.styleFrom(backgroundColor: _contactName != null ? AppColors.accent.withAlpha(50) : AppColors.surfaceVariant),
                    icon: Icon(Icons.person_pin_circle_outlined, color: _contactName != null ? AppColors.accent : AppColors.text),
                    tooltip: 'Spoof Caller ID',
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _isSaving ? null : () { HapticFeedback.mediumImpact(); _saveTask(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Add Task', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ],
      ),
    );
  }
}
