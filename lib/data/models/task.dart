enum TaskStatusEnum { pending, completed, missed, snoozed, accepted }

class Task {
  final String id;
  final String title;
  final String originalTranscript;
  final DateTime dueDateTime;
  final TaskStatusEnum status;
  final String? audioPath;
  final String? routineDays;
  final String? contactName;
  final String? contactNumber;
  final String? voiceNotePath;
  final bool isNonPriority;
  
  final bool isAllDay;
  final String timeBlockBucket;

  Task({
    required this.id,
    required this.title,
    required this.originalTranscript,
    required int dueTimestamp,
    required this.status,
    this.audioPath,
    this.routineDays,
    this.contactName,
    this.contactNumber,
    this.voiceNotePath,
    this.isNonPriority = false,
    this.isAllDay = false,
    this.timeBlockBucket = 'none',
  }) : dueDateTime = DateTime.fromMillisecondsSinceEpoch(dueTimestamp);

  // Getter required by telecom_service.dart and DB layers
  int get dueTimestamp => dueDateTime.millisecondsSinceEpoch;

  // Helper for new task creation
  factory Task.create({
    required String title,
    required String originalTranscript,
    required int dueTimestamp,
    bool isAllDay = false,
    String timeBlockBucket = 'none',
    String? audioPath,
    dynamic routineDays, // Changed to dynamic to accept List<String> from capture_sheet.dart
    String? contactName,
    String? contactNumber,
    String? voiceNotePath,
    bool isNonPriority = false,
  }) {
    // Automatically convert List<String> to a comma-separated String for SQLite
    String? parsedRoutineDays;
    if (routineDays is List) {
      parsedRoutineDays = routineDays.join(',');
    } else if (routineDays is String) {
      parsedRoutineDays = routineDays;
    }

    return Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      originalTranscript: originalTranscript,
      dueTimestamp: dueTimestamp,
      status: TaskStatusEnum.pending,
      isAllDay: isAllDay,
      timeBlockBucket: timeBlockBucket,
      audioPath: audioPath,
      routineDays: parsedRoutineDays,
      contactName: contactName,
      contactNumber: contactNumber,
      voiceNotePath: voiceNotePath,
      isNonPriority: isNonPriority,
    );
  }

  // Required by database_helper.dart for inserting tasks
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'originalTranscript': originalTranscript,
      'due_date': dueTimestamp,
      'status': status.name.toUpperCase(),
      'audioPath': audioPath,
      'routineDays': routineDays,
      'contactName': contactName,
      'contact_number': contactNumber,
      'voice_note_path': voiceNotePath,
      'is_non_priority': isNonPriority ? 1 : 0,
      'is_all_day': isAllDay ? 1 : 0,
      'time_block_bucket': timeBlockBucket,
    };
  }

  // Required by database_helper.dart for reading tasks
  factory Task.fromMap(Map<String, dynamic> map) {
    // Safely parse status string back to enum
    TaskStatusEnum parsedStatus = TaskStatusEnum.pending;
    if (map['status'] != null) {
      final statusStr = map['status'].toString().toLowerCase();
      parsedStatus = TaskStatusEnum.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => TaskStatusEnum.pending,
      );
    }

    return Task(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: map['title']?.toString() ?? '',
      originalTranscript: map['originalTranscript']?.toString() ?? '',
      // Fallback logic to check multiple possible DB column names
      dueTimestamp: (map['due_date'] as int?) ?? (map['dueTimestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      status: parsedStatus,
      audioPath: map['audioPath']?.toString(),
      routineDays: map['routineDays']?.toString(),
      contactName: map['contactName']?.toString(),
      contactNumber: map['contact_number']?.toString() ?? map['contactNumber']?.toString(),
      voiceNotePath: map['voice_note_path']?.toString() ?? map['voiceNotePath']?.toString(),
      isNonPriority: (map['is_non_priority'] == 1) || (map['isNonPriority'] == 1),
      isAllDay: (map['is_all_day'] == 1) || (map['isAllDay'] == 1),
      timeBlockBucket: map['time_block_bucket']?.toString() ?? map['timeBlockBucket']?.toString() ?? 'none',
    );
  }
}
