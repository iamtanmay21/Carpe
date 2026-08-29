import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import 'package:carpediem/services/database_helper.dart';
import '../data/models/task.dart';
import 'capture_sheet.dart';
import 'calendar_history_screen.dart';
import 'settings_screen.dart';

// --- NEW PIPELINE IMPORTS ---
import '../services/telecom_service.dart';
import '../services/voice_input_controller.dart';
import '../services/assistant_executor.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Task> _tasks = [];
  bool _loading = true;
  String _selectedTab = 'ALL';

  int _completedCount = 0;
  int _missedCount = 0;
  double _successRate = 0.0;

  // --- VOICE OVERLAY STATE ---
  final FlutterTts _tts = FlutterTts();
  final VoiceInputController _voiceController = VoiceInputController();
  
  bool _isProcessing = false;
  String _lastProcessedTranscript = "";

  // --- TRANSCRIPT EDITING STATE ---
  final TextEditingController _transcriptEditController = TextEditingController();
  final FocusNode _transcriptFocusNode = FocusNode();
  bool _isEditingTranscript = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _initTTS();
    
    // Bind the Voice Controller to the UI
    _voiceController.addListener(_onVoiceStateChanged);
  }

  @override
  void dispose() {
    _voiceController.removeListener(_onVoiceStateChanged);
    _voiceController.dispose();
    _tts.stop();
    _transcriptEditController.dispose();
    _transcriptFocusNode.dispose();
    super.dispose();
  }

  void _onVoiceStateChanged() {
    // 1. Trigger a UI rebuild for live mic changes
    setState(() {});

    // 2. Intercept Finalized Transcripts exactly once
    if (!_voiceController.isListening && 
        _voiceController.finalizedTranscript.isNotEmpty && 
        !_isProcessing &&
        !_isEditingTranscript) { // Safety lock: Don't auto-execute if user is manually typing
          
      final textToProcess = _voiceController.finalizedTranscript;

      if (textToProcess == _lastProcessedTranscript) {
        _voiceController.clearTranscript();
        return;
      }
      _lastProcessedTranscript = textToProcess;
      
      // Wipe the controller immediately so it doesn't loop
      _voiceController.clearTranscript();
      
      _processVoiceCommand(textToProcess);
    }
  }

  Future<void> _initTTS() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceName = prefs.getString('tts_voice_name');
    final voiceLocale = prefs.getString('tts_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
    } else {
      // Fallback to the requested preferred locale if no custom voice is saved.
      await _tts.setLanguage('en-IN');
    }
    await _tts.setSpeechRate(0.5); // Slower, natural conversational pace.
    await _tts.setPitch(1.0);
  }

  Future<void> _loadTasks() async {
    final tasks = await DatabaseHelper.instance.getAllTasks();
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
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
    });
    DatabaseHelper.instance.deleteTask(task.id);
    TelecomService.cancelNativeAlarm(task.id); 
  }

  Future<void> _markComplete(Task task) async {
    HapticFeedback.mediumImpact();
    await DatabaseHelper.instance.updateTaskStatus(task.id, 'COMPLETED');
    TelecomService.cancelNativeAlarm(task.id); 
    await _loadTasks();
  }

  // --- TRANSCRIPT EDITING HANDLERS ---
  
  Future<void> _startEditingTranscript() async {
    if (_voiceController.isListening) {
      await _voiceController.stopListening();
    }
    
    setState(() {
      _isEditingTranscript = true;
      _transcriptEditController.text = _voiceController.currentTranscript;
    });
    
    _transcriptFocusNode.requestFocus();
  }

  void _submitEditedTranscript() {
    final text = _transcriptEditController.text.trim();
    
    setState(() {
      _isEditingTranscript = false;
    });
    
    _transcriptEditController.clear();
    
    if (text.isNotEmpty) {
      // Treat the manually typed text identically to voice execution
      _lastProcessedTranscript = text;
      _voiceController.clearTranscript();
      _processVoiceCommand(text);
    }
  }

  Future<void> _toggleMic() async {
    HapticFeedback.lightImpact();
    // Dismiss editing mode if user taps the big mic button
    if (_isEditingTranscript) {
      setState(() {
        _isEditingTranscript = false;
      });
    }

    if (_voiceController.isListening) {
      await _voiceController.stopListening();
    } else {
      _lastProcessedTranscript = "";
      await _voiceController.startListening();
    }
  }

  Future<void> _processVoiceCommand(String textToProcess) async {
    if (_isProcessing) return; // Safety lock

    setState(() => _isProcessing = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing command...'), duration: Duration(seconds: 1)),
    );

    try {
      // 1. Send text to the new Executor Brain
      final result = await AssistantExecutor.instance.executeVoiceCommand(textToProcess);
      
      // 2. UI UPDATE FIRST! 
      // We load tasks immediately so the screen updates instantly regardless of TTS.
      await _loadTasks();
      
      // 3. UI Snackbar Feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.feedbackMessage.isNotEmpty ? result.feedbackMessage : "Command Executed."), duration: const Duration(seconds: 3)),
        );
      }

      // 4. Play the audio feedback (FIRE AND FORGET - NO AWAIT)
      if (result.feedbackMessage.isNotEmpty) {
        
        // Dynamic Completion Handler for Clarification Loops
        if (result.requiresUserClarification) {
          _tts.setCompletionHandler(() {
            _voiceController.listenForClarification();
            _tts.setCompletionHandler(() {}); // Clear handler to prevent memory leaks
          });
        } else {
          _tts.setCompletionHandler(() {}); // Ensure it doesn't trigger unexpectedly
        }
        
        // No await here! This prevents freezing if TTS sleeps.
        _tts.speak(result.feedbackMessage).catchError((e) {
          debugPrint("TTS Error: $e");
        });
      } else if (result.requiresUserClarification) {
        // Fallback: If there's no feedback message but clarification is needed
        _voiceController.listenForClarification();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Carpe Diem', style: GoogleFonts.outfit(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary), onPressed: _loadTasks)
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildStatsHeader(),
          _buildTabSelector(),
          
          // Live Transcript Overlay & Editor
          if (_voiceController.isListening || _isProcessing || _isEditingTranscript)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: _isEditingTranscript
                  ? TextField(
                      controller: _transcriptEditController,
                      focusNode: _transcriptFocusNode,
                      style: GoogleFonts.inter(color: AppColors.accent, fontSize: 16, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: "Type your command...",
                        hintStyle: GoogleFonts.inter(color: AppColors.accent.withOpacity(0.5), fontStyle: FontStyle.italic),
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send_rounded, color: AppColors.accent),
                          onPressed: _submitEditedTranscript,
                        ),
                      ),
                      onSubmitted: (_) => _submitEditedTranscript(),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _startEditingTranscript,
                      child: Text(
                        _voiceController.currentTranscript.isEmpty 
                            ? "Listening... (Tap to type)" 
                            : '"${_voiceController.currentTranscript}" (Tap to edit)',
                        style: GoogleFonts.inter(color: AppColors.accent, fontSize: 16, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _filteredTasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), 
                        itemCount: _filteredTasks.length,
                        itemBuilder: (context, index) {
                          return _buildTaskCard(_filteredTasks[index])
                              .animate()
                              .fade(duration: 400.ms, delay: (50 * index).ms)
                              .slideY(begin: 0.1, duration: 400.ms, curve: Curves.easeOutQuart);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _buildAuraMic(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildAuraMic() {
    return GestureDetector(
      onTap: _toggleMic,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: _voiceController.isListening
              ? [
                  BoxShadow(color: AppColors.auraStart.withOpacity(0.6), blurRadius: 30, spreadRadius: 10),
                  BoxShadow(color: AppColors.auraEnd.withOpacity(0.4), blurRadius: 60, spreadRadius: 20),
                ]
              : [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10)),
                ],
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _voiceController.isListening
                  ? [AppColors.error, AppColors.accentGradientMid]
                  : [AppColors.auraStart, AppColors.auraEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            _voiceController.isListening ? Icons.mic : Icons.mic_none,
            size: 36,
            color: Colors.white,
          )
          .animate(target: _voiceController.isListening ? 1 : 0)
          .scale(end: const Offset(1.2, 1.2), duration: 600.ms, curve: Curves.easeInOut)
          .shimmer(duration: 1200.ms, delay: 400.ms, color: Colors.white24, angle: 1),
        ),
      ).animate(
        onPlay: (controller) => _voiceController.isListening ? controller.repeat(reverse: true) : controller.stop(),
        target: _voiceController.isListening ? 1 : 0
      ).scaleXY(end: 1.05, duration: 800.ms, curve: Curves.easeInOut),
    );
  }

  Widget _buildStatsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildStatItem('Success', '${_successRate.toStringAsFixed(0)}%', AppColors.accent)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatItem('Done', '$_completedCount', AppColors.success)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatItem('Missed', '$_missedCount', AppColors.error)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String val, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: col.withAlpha(40)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))
        ]
      ),
      child: Column(
        children: [
          Text(val, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: col)),
          const SizedBox(height: 4),
          Text(title, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    final tabs = ['ALL', 'UPCOMING', 'MISSED', 'DONE'];
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.4), 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withOpacity(0.5))
      ),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedTab == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isSelected) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = tab);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: isSelected ? const LinearGradient(
                    colors: [AppColors.surfaceElevated, AppColors.surfaceVariant],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter
                  ) : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  tab,
                  style: GoogleFonts.inter(
                    fontSize: 12, 
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, 
                    color: isSelected ? AppColors.text : AppColors.textMuted
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final isDone = task.status == TaskStatusEnum.completed || task.status == TaskStatusEnum.accepted;
    
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.error.withOpacity(0.1), AppColors.error.withOpacity(0.4)]),
          borderRadius: BorderRadius.circular(20)
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 28),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        _deleteTaskOptimistic(task);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDone 
                ? [AppColors.surfaceVariant.withOpacity(0.6), AppColors.surface.withOpacity(0.8)]
                : [AppColors.surfaceElevated.withOpacity(0.9), AppColors.surfaceVariant.withOpacity(0.7)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDone ? AppColors.divider.withOpacity(0.3) : AppColors.accent.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: GoogleFonts.inter(
                            fontSize: 16, 
                            fontWeight: FontWeight.w600, 
                            color: isDone ? AppColors.textSecondary : AppColors.text, 
                            decoration: isDone ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.textSecondary,
                            decorationThickness: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: task.status == TaskStatusEnum.missed 
                                    ? AppColors.error.withOpacity(0.1) 
                                    : AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    task.status == TaskStatusEnum.missed ? Icons.warning_rounded : Icons.access_time_rounded, 
                                    size: 14, 
                                    color: task.status == TaskStatusEnum.missed ? AppColors.error : AppColors.accent
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${task.dueDateTime.day}/${task.dueDateTime.month} · ${task.dueDateTime.hour}:${task.dueDateTime.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12, 
                                      fontWeight: FontWeight.w600,
                                      color: task.status == TaskStatusEnum.missed ? AppColors.error : AppColors.accent
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (task.status == TaskStatusEnum.pending)
                    GestureDetector(
                      onTap: () => _markComplete(task),
                      child: Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success.withOpacity(0.1),
                          border: Border.all(color: AppColors.success.withOpacity(0.3), width: 2),
                        ),
                        child: const Icon(Icons.check_rounded, color: AppColors.success, size: 28),
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                       .scaleXY(end: 1.05, duration: 1.seconds, curve: Curves.easeInOut),
                    )
                  else if (isDone)
                    const Icon(Icons.task_alt_rounded, color: AppColors.success, size: 28)
                        .animate().scale(delay: 200.ms, duration: 400.ms, curve: Curves.elasticOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt_rounded, size: 56, color: AppColors.textMuted.withAlpha(80)),
          const SizedBox(height: 12),
          Text('No $_selectedTab tasks found', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.background),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Carpe Diem', style: GoogleFonts.outfit(color: AppColors.accent, fontSize: 26, fontWeight: FontWeight.bold)),
                Text('Seize the day.', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_task_rounded, color: AppColors.success),
            title: Text('Add Task Manually', style: GoogleFonts.inter(color: AppColors.text)),
            onTap: () {
              Navigator.pop(context); 
              CaptureSheet.show(context).then((_) => _loadTasks());
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded, color: AppColors.warning),
            title: Text('Calendar & History', style: GoogleFonts.inter(color: AppColors.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarHistoryScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded, color: AppColors.textSecondary),
            title: Text('Settings (TTS Voice)', style: GoogleFonts.inter(color: AppColors.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }
}
