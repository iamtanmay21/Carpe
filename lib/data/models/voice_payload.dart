enum VoiceIntent { create, query, reschedule, bulkMove, bulkCancel, deleteTask, unknown }

class RelativeDelta {
  final int amount;
  final String unit; // 'minutes', 'hours', 'days'
  final int direction; // 1 for forward/postpone, -1 for bring forward

  RelativeDelta({
    required this.amount,
    required this.unit,
    required this.direction,
  });
}

class FilterRange {
  final DateTime start;
  final DateTime end;

  FilterRange({required this.start, required this.end});
}

class VoicePayload {
  final VoiceIntent intent;
  final String? taskTitle;
  final DateTime? targetTime;
  final FilterRange? filterRange;
  final RelativeDelta? relativeDelta;
  final String statusFilter; // 'PENDING', 'COMPLETED', 'ALL'
  final bool isBulk;
  final String rawTranscript;

  VoicePayload({
    required this.intent,
    this.taskTitle,
    this.targetTime,
    this.filterRange,
    this.relativeDelta,
    this.statusFilter = 'PENDING',
    this.isBulk = false,
    required this.rawTranscript,
  });
}
