import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/theme.dart';
import 'package:carpediem/services/database_helper.dart';
import '../data/models/task.dart';
import 'capture_sheet.dart';
import 'calendar_history_screen.dart';
import 'settings_screen.dart';

import '../services/telecom_service.dart';
import '../services/voice_input_controller.dart';
import '../services/assistant_executor.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

// 1. ADDED: WidgetsBindingObserver to detect when the app returns from the call screen
class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  List<Task> _tasks = [];
  bool _loading = true;
  String _selectedTab = 'ALL';

  int _completedCount = 0;
  int _missedCount = 0;
  double _successRate = 0.0;

  final FlutterTts _tts = FlutterTts();
  final VoiceInputController _voiceController = VoiceInputController();
  
  bool _isProcessing = false;
  String _lastProcessedTranscript = "";

  final TextEditingController _transcriptEditController = TextEditingController();
  final FocusNode _transcriptFocusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // 2. ADDED: Register the lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    _loadTasks();
    _initTTS();
    
    _voiceController.addListener(_onVoiceStateChanged);
    _transcriptEditController.addListener(() {
      setState(() {
        _hasText = _transcriptEditController.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    // 3. ADDED: Remove the lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _voiceController.removeListener(_onVoiceStateChanged);
    _voiceController.dispose();
    _tts.stop();
    _transcriptEditController.dispose();
    _transcriptFocusNode.dispose();
    super.dispose();
  }

  // 4. ADDED: Refresh database when app comes to foreground after Telecom call ends
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTasks(); 
    }
  }

  void _onVoiceStateChanged() {
    setState(() {});

    if (!_voiceController.isListening && 
        _voiceController.finalizedTranscript.isNotEmpty && 
        !_isProcessing) {
          
      final textToProcess = _voiceController.finalizedTranscript;

      if (textToProcess == _lastProcessedTranscript) {
        _voiceController.clearTranscript();
        return;
      }
      
      _transcriptEditController.text = textToProcess;
      _lastProcessedTranscript = textToProcess;
      _voiceController.clearTranscript();
      _processCommand(textToProcess);
    } else if (_voiceController.isListening && _voiceController.currentTranscript.isNotEmpty) {
      _transcriptEditController.text = _voiceController.currentTranscript;
    }
  }

  Future<void> _initTTS() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceName = prefs.getString('tts_voice_name');
    final voiceLocale = prefs.getString('tts_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
    } else {
      await _tts.setLanguage('en-IN');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> _loadTasks() async {
    final now = DateTime.now();
    
    // 5. THE FIX: 3-Minute Grace Period. Do not mark MISSED if it is currently ringing.
    final expiredThreshold = now.subtract(const Duration(minutes: 3));
    
    var tasks = await DatabaseHelper.instance.getAllTasks();

    bool needsRefresh = false;
    for (final task in tasks) {
      // Check against the threshold instead of exact 'now'
      if (task.status == TaskStatusEnum.pending &&
          task.dueDateTime.isBefore(expiredThreshold)) {
        await DatabaseHelper.instance.updateTaskStatus(task.id, 'MISSED');
        needsRefresh = true;
      }
    }

    if (needsRefresh) {
      tasks = await DatabaseHelper.instance.getAllTasks();
    }
    
    tasks.sort((a, b) => a.dueDateTime.compareTo(b.dueDateTime));
    
    final completed = tasks.where((t) => t.status == TaskStatusEnum.completed).length;
    final missed = tasks.where((t) => t.status == TaskStatusEnum.missed).length;
    final rate = (completed + missed) > 0 ? (completed / (completed + missed)) * 100 : 0.0;

    if (mounted) {
      setState(() {
        _tasks = tasks;
        _completedCount = completed;
        _missedCount = missed;
        _successRate = rate;
        _loading = false;
      });
    }
  }

  List<Task> get _filteredTasks {
    switch (_selectedTab) {
      case 'UPCOMING':
        return _tasks.where((t) => t.status == TaskStatusEnum.pending || t.status == TaskStatusEnum.snoozed).toList();
      case 'MISSED':
        return _tasks.where((t) => t.status == TaskStatusEnum.missed).toList();
      case 'DONE':
        return _tasks.where((t) => t.status == TaskStatusEnum.completed || t.status == TaskStatusEnum.accepted).toList();
      default:
        return _tasks;
    }
  }

  void _deleteTaskOptimistic(Task task) {
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
    DatabaseHelper.instance.deleteTask(task.id);
    TelecomService.cancelNativeAlarm(task.id); 
  }

  Future<void> _markComplete(Task task) async {
    HapticFeedback.mediumImpact();
    await DatabaseHelper.instance.updateTaskStatus(task.id, 'COMPLETED');
    TelecomService.cancelNativeAlarm(task.id); 
    await _loadTasks();
  }

  Future<void> _markPending(Task task) async {
    await DatabaseHelper.instance.database.then(
      (db) => db.update(
        'tasks',
        {'status': 'PENDING'},
        where: 'id = ?',
        whereArgs: [task.id],
      ),
    );
    await TelecomService.scheduleNativeAlarm(task);
    await _loadTasks();
  }

  Future<void> _toggleMicOrSend() async {
    HapticFeedback.lightImpact();
    
    if (_hasText) {
      final text = _transcriptEditController.text.trim();
      _transcriptFocusNode.unfocus();
      _processCommand(text);
      return;
    }

    if (_voiceController.isListening) {
      await _voiceController.stopListening();
    } else {
      _lastProcessedTranscript = "";
      _transcriptEditController.clear();
      await _voiceController.startListening();
    }
  }

  Future<void> _processCommand(String textToProcess) async {
    if (_isProcessing || textToProcess.isEmpty) return;

    setState(() => _isProcessing = true);
    
    try {
      final result = await AssistantExecutor.instance.executeVoiceCommand(textToProcess);
      
      _transcriptEditController.clear();
      await _loadTasks();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.feedbackMessage.isNotEmpty ? result.feedbackMessage : "Command Executed."), duration: const Duration(seconds: 3)),
        );
      }

      if (result.feedbackMessage.isNotEmpty) {
        if (result.requiresUserClarification) {
          _tts.setCompletionHandler(() {
            _voiceController.listenForClarification();
            _tts.setCompletionHandler(() {});
          });
        } else {
          _tts.setCompletionHandler(() {});
        }
        _tts.speak(result.feedbackMessage).catchError((e) => debugPrint("TTS Error: $e"));
      } else if (result.requiresUserClarification) {
        _voiceController.listenForClarification();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showEditTaskSheet(Task task) {
    String editTitle = task.title;
    DateTime editDate = task.dueDateTime;
    bool editNonPriority = task.isNonPriority;
    String editContact = task.contactNumber ?? "";
    String editVoiceNote = task.voiceNotePath ?? "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
              top: 24, left: 24, right: 24
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Edit Task", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
                const SizedBox(height: 16),
                
                TextField(
                  controller: TextEditingController(text: editTitle)..selection = TextSelection.collapsed(offset: editTitle.length),
                  onChanged: (val) => editTitle = val,
                  style: GoogleFonts.inter(color: AppColors.text, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: "Task Title",
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(context: context, initialDate: editDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (picked != null) {
                            setSheetState(() => editDate = DateTime(picked.year, picked.month, picked.day, editDate.hour, editDate.minute));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Text("${editDate.day}/${editDate.month}/${editDate.year}", style: GoogleFonts.inter(color: AppColors.text)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(editDate));
                          if (picked != null) {
                            setSheetState(() => editDate = DateTime(editDate.year, editDate.month, editDate.day, picked.hour, picked.minute));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, size: 16, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Text(TimeOfDay.fromDateTime(editDate).format(context), style: GoogleFonts.inter(color: AppColors.text)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Notification Only (No Call)",
                    style: GoogleFonts.inter(
                      color: AppColors.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    "Disables native alarm ring and TTS",
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: editNonPriority,
                  activeColor: AppColors.accent,
                  onChanged: (val) =>
                      setSheetState(() => editNonPriority = val),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: editNonPriority ? 0.4 : 1.0,
                  child: IgnorePointer(
                    ignoring: editNonPriority,
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () async {
                            final contact = await _pickEditContact();
                            if (contact != null && context.mounted) {
                              setSheetState(() => editContact = contact);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone_outlined,
                                  size: 18,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  editContact.isEmpty
                                      ? "Select Caller ID..."
                                      : editContact,
                                  style: GoogleFonts.inter(color: AppColors.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final voiceNote =
                                await _recordEditVoiceNote(context);
                            if (voiceNote != null && context.mounted) {
                              setSheetState(() => editVoiceNote = voiceNote);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.mic_none_outlined,
                                  size: 18,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  editVoiceNote.isEmpty
                                      ? "Record Audio Override..."
                                      : "Audio Recorded",
                                  style: GoogleFonts.inter(color: AppColors.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () {
                        _deleteTaskOptimistic(task);
                        Navigator.pop(context);
                      },
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
                        final now = DateTime.now();
                        final isPast = editDate.isBefore(now);
                        final newStatus = isPast ? 'MISSED' : 'PENDING';

                        await DatabaseHelper.instance.database.then(
                          (db) => db.update(
                            'tasks',
                            {
                              'title': editTitle,
                              'due_date': editDate.millisecondsSinceEpoch,
                              'is_non_priority': editNonPriority ? 1 : 0,
                              'contact_number': editContact,
                              'voice_note_path': editVoiceNote,
                              'status': newStatus,
                            },
                            where: 'id = ?',
                            whereArgs: [task.id],
                          ),
                        );

                        if (!isPast && !editNonPriority) {
                          final updatedTask = Task(
                            id: task.id,
                            title: editTitle,
                            originalTranscript: task.originalTranscript,
                            dueTimestamp: editDate.millisecondsSinceEpoch,
                            status: TaskStatusEnum.pending,
                            audioPath: task.audioPath,
                            routineDays: task.routineDays,
                            contactName: task.contactName,
                            contactNumber: editContact,
                            voiceNotePath: editVoiceNote,
                            isAllDay: task.isAllDay,
                            timeBlockBucket: task.timeBlockBucket,
                          );
                          await TelecomService.scheduleNativeAlarm(updatedTask);
                        } else {
                          await TelecomService.cancelNativeAlarm(task.id);
                        }

                        await _loadTasks();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text("Save Changes", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickEditContact() async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      return null;
    }

    final contact = await FlutterContacts.openExternalPick();
    if (contact == null) return null;

    final fullContact = await FlutterContacts.getContact(contact.id);
    if (fullContact == null || fullContact.phones.isEmpty) return null;

    return fullContact.phones.first.number;
  }

  Future<String?> _recordEditVoiceNote(BuildContext sheetContext) async {
    final recorder = AudioRecorder();
    String? recordingPath;
    bool isRecording = false;

    final savedPath = await showModalBottomSheet<String>(
      context: sheetContext,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setRecordingState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isRecording ? 'Recording audio override...' : 'Record Audio Override',
                style: GoogleFonts.outfit(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              IconButton(
                iconSize: 48,
                color: isRecording ? AppColors.error : AppColors.accent,
                icon: Icon(isRecording ? Icons.stop_circle_outlined : Icons.mic),
                onPressed: () async {
                  if (isRecording) {
                    recordingPath = await recorder.stop();
                    setRecordingState(() => isRecording = false);
                    return;
                  }

                  if (await recorder.hasPermission()) {
                    final directory = await getApplicationDocumentsDirectory();
                    final path = p.join(
                      directory.path,
                      'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
                    );
                    await recorder.start(
                      const RecordConfig(encoder: AudioEncoder.aacLc),
                      path: path,
                    );
                    setRecordingState(() => isRecording = true);
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isRecording || recordingPath == null
                    ? null
                    : () => Navigator.pop(context, recordingPath),
                child: const Text('Use Recording'),
              ),
            ],
          ),
        ),
      ),
    );

    if (isRecording) await recorder.stop();
    await recorder.dispose();
    return savedPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Carpe Diem', style: GoogleFonts.outfit(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary), onPressed: _loadTasks)],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildStatsHeader(),
          _buildTabSelector(),
          
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _filteredTasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        itemCount: _filteredTasks.length,
                        itemBuilder: (context, index) {
                          return _buildTimelineCard(_filteredTasks[index], index == _filteredTasks.length - 1)
                              .animate()
                              .fade(duration: 400.ms, delay: (50 * index).ms)
                              .slideY(begin: 0.1, duration: 400.ms, curve: Curves.easeOutQuart);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildPersistentChatBar(),
    );
  }

  Widget _buildTimelineCard(Task task, bool isLast) {
    final isDone = task.status == TaskStatusEnum.completed || task.status == TaskStatusEnum.accepted;
    final timeString = TimeOfDay.fromDateTime(task.dueDateTime).format(context);
    final dateString = "${task.dueDateTime.day}/${task.dueDateTime.month}/${task.dueDateTime.year}";
    
    final dotColor = isDone ? AppColors.success : (task.status == TaskStatusEnum.missed ? AppColors.error : AppColors.accent);

    return GestureDetector(
      onTap: () => _showEditTaskSheet(task),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 65,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  timeString,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: dotColor, fontSize: 13),
                ),
              ),
            ),
            Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 18),
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: isDone ? dotColor : AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2.5),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AppColors.divider.withOpacity(0.5)),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDone ? AppColors.surfaceVariant.withOpacity(0.4) : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider.withOpacity(0.3)),
                  boxShadow: isDone ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: GoogleFonts.inter(
                              fontSize: 16, 
                              fontWeight: FontWeight.w600,
                              color: isDone ? AppColors.textSecondary : AppColors.text,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (!isDone)
                          GestureDetector(
                            onTap: () => _markComplete(task),
                            child: const Icon(Icons.circle_outlined, color: AppColors.textMuted, size: 22),
                          )
                        else
                          GestureDetector(
                            onTap: () => _markPending(task),
                            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(dateString, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                        const Spacer(),
                        if (task.status == TaskStatusEnum.missed)
                          Text("Missed", style: GoogleFonts.inter(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersistentChatBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider.withOpacity(0.5))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _transcriptEditController,
                focusNode: _transcriptFocusNode,
                style: GoogleFonts.inter(color: AppColors.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: _voiceController.isListening ? "Listening..." : "Message Assistant...",
                  hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _toggleMicOrSend(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _toggleMicOrSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isProcessing
                      ? [AppColors.textMuted, AppColors.textSecondary]
                      : _hasText
                          ? [AppColors.accent, AppColors.accentGradientMid]
                          : _voiceController.isListening
                              ? [AppColors.error, AppColors.accent]
                              : [AppColors.auraStart, AppColors.auraEnd],
                ),
                boxShadow: [
                  if (_voiceController.isListening || _hasText)
                    BoxShadow(color: AppColors.accent.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)
                ],
              ),
              child: _isProcessing 
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Icon(
                      _hasText ? Icons.send_rounded : (_voiceController.isListening ? Icons.mic : Icons.mic_none),
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() { return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [Expanded(child: _buildStatItem('Success', '${_successRate.toStringAsFixed(0)}%', AppColors.accent)), const SizedBox(width: 8), Expanded(child: _buildStatItem('Done', '$_completedCount', AppColors.success)), const SizedBox(width: 8), Expanded(child: _buildStatItem('Missed', '$_missedCount', AppColors.error)),],),); }
  Widget _buildStatItem(String title, String val, Color col) { return Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppColors.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withAlpha(40)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]), child: Column(children: [Text(val, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: col)), const SizedBox(height: 4), Text(title, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, letterSpacing: 0.5)),],),); }
  Widget _buildTabSelector() { final tabs = ['ALL', 'UPCOMING', 'MISSED', 'DONE']; return Container(height: 44, margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: AppColors.surfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider.withOpacity(0.5))), child: Row(children: tabs.map((tab) { final isSelected = _selectedTab == tab; return Expanded(child: GestureDetector(onTap: () { if (!isSelected) { HapticFeedback.selectionClick(); setState(() => _selectedTab = tab); } }, child: AnimatedContainer(duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic, decoration: BoxDecoration(gradient: isSelected ? const LinearGradient(colors: [AppColors.surfaceElevated, AppColors.surfaceVariant], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null, borderRadius: BorderRadius.circular(14), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],), alignment: Alignment.center, child: Text(tab, style: GoogleFonts.inter(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.text : AppColors.textMuted),),),),); }).toList(),),); }
  Widget _buildEmptyState() { return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.task_alt_rounded, size: 56, color: AppColors.textMuted.withAlpha(80)), const SizedBox(height: 12), Text('No $_selectedTab tasks found', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 16)),],),); }
  Drawer _buildDrawer() { return Drawer(backgroundColor: AppColors.surface, child: ListView(padding: EdgeInsets.zero, children: [DrawerHeader(decoration: const BoxDecoration(color: AppColors.background), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [Text('Carpe Diem', style: GoogleFonts.outfit(color: AppColors.accent, fontSize: 26, fontWeight: FontWeight.bold)), Text('Seize the day.', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),],),), ListTile(leading: const Icon(Icons.add_task_rounded, color: AppColors.success), title: Text('Add Task Manually', style: GoogleFonts.inter(color: AppColors.text)), onTap: () { Navigator.pop(context); CaptureSheet.show(context).then((_) => _loadTasks()); },), ListTile(leading: const Icon(Icons.calendar_month_rounded, color: AppColors.warning), title: Text('Calendar & History', style: GoogleFonts.inter(color: AppColors.text)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarHistoryScreen())); },), ListTile(leading: const Icon(Icons.settings_rounded, color: AppColors.textSecondary), title: Text('Settings (TTS Voice)', style: GoogleFonts.inter(color: AppColors.text)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },),],),); }
}
