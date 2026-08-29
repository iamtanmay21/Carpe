import 'intent_blueprint.dart';

class ExecutionResult {
  final String rawTranscript;
  final CommandIntent intent;
  final bool success;
  final String feedbackMessage;
  final List<Map<String, dynamic>> affectedTasks;
  final List<Map<String, dynamic>> conflictingTasks;
  final bool requiresUserClarification;
  final String? clarificationPrompt;

  const ExecutionResult({
    required this.rawTranscript,
    required this.intent,
    required this.success,
    required this.feedbackMessage,
    required this.affectedTasks,
    required this.conflictingTasks,
    required this.requiresUserClarification,
    this.clarificationPrompt,
  });
}
