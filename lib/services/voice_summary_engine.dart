import 'package:intl/intl.dart';
import '../models/intent_blueprint.dart';

class VoiceSummaryEngine {
  
  static String _formatRelativeDay(DateTime targetDay) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDay.year, targetDay.month, targetDay.day);
    
    final diff = target.difference(today).inDays;
    if (diff == 0) return "today";
    if (diff == 1) return "tomorrow";
    if (diff == -1) return "yesterday";
    
    // If within a week, use day name, else use explicit date
    if (diff > 1 && diff < 7) {
      return DateFormat('EEEE').format(targetDay);
    }
    return "on ${DateFormat('MMMM d').format(targetDay)}";
  }

  static String _formatTime(int epochMs) {
    return DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(epochMs));
  }

  static String summarizeQuery(List<Map<String, dynamic>> tasks, DateTime targetDay) {
    final dayStr = _formatRelativeDay(targetDay);
    
    if (tasks.isEmpty) {
      return "Your schedule is completely clear for $dayStr.";
    }
    
    if (tasks.length == 1) {
      final task = tasks.first;
      return "You have one task: ${task['title']} at ${_formatTime(task['due_date'] as int)}.";
    }
    
    if (tasks.length <= 3) {
      String summary = "You have ${tasks.length} tasks: ";
      for (int i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        if (i == tasks.length - 1) {
          summary += "and ${task['title']} at ${_formatTime(task['due_date'] as int)}.";
        } else {
          summary += "${task['title']} at ${_formatTime(task['due_date'] as int)}, ";
        }
      }
      return summary;
    }
    
    // Macro-Anchor for >3 tasks
    final firstTask = tasks.first;
    final lastTask = tasks.last;
    return "You have ${tasks.length} tasks scheduled for $dayStr. You start with ${firstTask['title']} at ${_formatTime(firstTask['due_date'] as int)} and finish with ${lastTask['title']} at ${_formatTime(lastTask['due_date'] as int)}.";
  }

  static String summarizeMutation({
    required CommandIntent intent, 
    required String taskTitle, 
    DateTime? targetTime, 
    List<Map<String, dynamic>> conflicts = const []
  }) {
    String baseMessage = "";
    
    if (intent == CommandIntent.create || intent == CommandIntent.reschedule) {
      if (targetTime != null) {
        final dayStr = _formatRelativeDay(targetTime);
        final timeStr = DateFormat('h:mm a').format(targetTime);
        final action = intent == CommandIntent.create ? "Scheduled" : "Rescheduled";
        baseMessage = "$action $taskTitle for $dayStr at $timeStr.";
      } else {
        baseMessage = "Saved $taskTitle.";
      }
    } else if (intent == CommandIntent.deleteTask) {
      baseMessage = "Deleted task $taskTitle.";
    }

    if (conflicts.length == 1) {
      baseMessage += " Heads up: you also have ${conflicts.first['title']} at that time.";
    } else if (conflicts.length >= 2) {
      baseMessage += " Note: you have ${conflicts.length} overlapping tasks. Check your screen to adjust them.";
    }

    return baseMessage;
  }

  static String summarizeBulkMove(int count, String targetDayName, int conflictCount) {
    String message = "Moved $count tasks to $targetDayName.";
    if (conflictCount > 0) {
      message += " $conflictCount tasks have time overlaps.";
    }
    return message;
  }
}
