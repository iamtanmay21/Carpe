import '../models/intent_blueprint.dart';

enum AwaitingResolution { 
  disambiguateTask, 
  confirmCollision, 
  specifyTime 
}

enum SessionResolutionStatus { 
  aborted, 
  overrideWithNewCommand, 
  completed,
  unresolved 
}

class SessionResolutionResult {
  final SessionResolutionStatus status;
  final IntentBlueprint? resolvedBlueprint;
  final String? resolvedTaskId;

  const SessionResolutionResult._({
    required this.status,
    this.resolvedBlueprint,
    this.resolvedTaskId,
  });

  factory SessionResolutionResult.aborted() {
    return const SessionResolutionResult._(status: SessionResolutionStatus.aborted);
  }

  factory SessionResolutionResult.overrideWithNewCommand() {
    return const SessionResolutionResult._(status: SessionResolutionStatus.overrideWithNewCommand);
  }

  factory SessionResolutionResult.completed(IntentBlueprint blueprint, {String? taskId}) {
    return SessionResolutionResult._(
      status: SessionResolutionStatus.completed, 
      resolvedBlueprint: blueprint,
      resolvedTaskId: taskId,
    );
  }

  factory SessionResolutionResult.unresolved() {
    return const SessionResolutionResult._(status: SessionResolutionStatus.unresolved);
  }
}

class ActiveSession {
  final IntentBlueprint suspendedBlueprint;
  final AwaitingResolution expectedResolution;
  final List<Map<String, dynamic>> candidateTasks;
  final DateTime createdAt;

  ActiveSession({
    required this.suspendedBlueprint,
    required this.expectedResolution,
    required this.candidateTasks,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Expires after 30 seconds of inactivity
  bool get isExpired => DateTime.now().difference(createdAt).inSeconds > 30;
}

class SessionManager {
  SessionManager._privateConstructor();
  static final SessionManager instance = SessionManager._privateConstructor();

  ActiveSession? _currentSession;

  bool get hasActiveSession => _currentSession != null && !_currentSession!.isExpired;

  void startSession(
    IntentBlueprint blueprint, 
    AwaitingResolution resolution, 
    List<Map<String, dynamic>> candidates
  ) {
    _currentSession = ActiveSession(
      suspendedBlueprint: blueprint,
      expectedResolution: resolution,
      candidateTasks: candidates,
    );
  }

  void clearSession() {
    _currentSession = null;
  }

  Future<SessionResolutionResult> processInput(String rawInput) async {
    if (!hasActiveSession) {
      return SessionResolutionResult.unresolved();
    }

    final lowerInput = rawInput.toLowerCase().trim();
    final session = _currentSession!;

    // 1. Abort Interceptor
    final abortRegex = RegExp(r'^(never mind|cancel|stop|abort|forget it|quit|exit)\b');
    if (abortRegex.hasMatch(lowerInput)) {
      clearSession();
      return SessionResolutionResult.aborted();
    }

    // 2. Override Interceptor (User ignores clarification and gives a new command)
    final overrideRegex = RegExp(r'^(remind me to|add task|schedule|create|move|delete)\b');
    if (overrideRegex.hasMatch(lowerInput)) {
      clearSession();
      return SessionResolutionResult.overrideWithNewCommand();
    }

    // 3. Slot Resolution Routing
    switch (session.expectedResolution) {
      case AwaitingResolution.disambiguateTask:
        return _resolveDisambiguation(lowerInput, session);
      
      case AwaitingResolution.confirmCollision:
        return _resolveCollision(lowerInput, session);

      case AwaitingResolution.specifyTime:
        // Future implementation for missing time slots
        return SessionResolutionResult.unresolved();
    }
  }

  SessionResolutionResult _resolveDisambiguation(String input, ActiveSession session) {
    int? matchedIndex;

    // A. Check for Ordinal Selections ("first one", "second")
    if (RegExp(r'\b(first|1st|one|1)\b').hasMatch(input)) {
      matchedIndex = 0;
    } else if (RegExp(r'\b(second|2nd|two|2)\b').hasMatch(input)) {
      matchedIndex = 1;
    } else if (RegExp(r'\b(third|3rd|three|3)\b').hasMatch(input)) {
      matchedIndex = 2;
    }

    // B. Fallback to Title/Time Substring Matching ("the gym one", "the 3 pm one")
    if (matchedIndex == null) {
      for (int i = 0; i < session.candidateTasks.length; i++) {
        final task = session.candidateTasks[i];
        final title = (task['title'] as String).toLowerCase();
        
        // If the user says a word that uniquely matches one of the task titles
        if (title.contains(input) || input.contains(title)) {
          matchedIndex = i;
          break;
        }
      }
    }

    if (matchedIndex != null && matchedIndex < session.candidateTasks.length) {
      final selectedTask = session.candidateTasks[matchedIndex];
      final exactTitle = selectedTask['title'] as String;
      final taskId = selectedTask['id']?.toString();

      // Inject the exact resolved text target into a cloned Blueprint
      final resolvedBlueprint = IntentBlueprint(
        intent: session.suspendedBlueprint.intent,
        rawTextTarget: exactTitle, // Use exact title to guarantee execution match
        statusFilter: session.suspendedBlueprint.statusFilter,
        isBulk: session.suspendedBlueprint.isBulk,
        slots: session.suspendedBlueprint.slots,
        rawTranscript: session.suspendedBlueprint.rawTranscript,
      );

      clearSession();
      return SessionResolutionResult.completed(resolvedBlueprint, taskId: taskId);
    }

    return SessionResolutionResult.unresolved();
  }

  SessionResolutionResult _resolveCollision(String input, ActiveSession session) {
    // If asking "There is a task at 3 PM already. Still schedule it?"
    final yesRegex = RegExp(r'^(yes|yeah|yep|sure|do it|still schedule|continue)\b');
    
    if (yesRegex.hasMatch(input)) {
      // User confirms, proceed with the original blueprint
      final resolvedBlueprint = session.suspendedBlueprint;
      clearSession();
      return SessionResolutionResult.completed(resolvedBlueprint);
    }
    
    // If they say anything else, we assume abort
    clearSession();
    return SessionResolutionResult.aborted();
  }
}
