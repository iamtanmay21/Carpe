import 'dart:math' as math;

class DialogueEngine {
  static final _rand = math.Random();

  static String _withCarpeDiem(String base, {double chance = 0.25}) {
    if (_rand.nextDouble() <= chance) {
      return "$base Carpe diem!";
    }
    return base;
  }

  // MATHEMATICALLY ROBUST TIME FORMATTER
  static String _formatTime(DateTime time, bool isDateOnly) {
    if (isDateOnly) return "";
    int hr = time.hour;
    String ampm = hr >= 12 ? "PM" : "AM";
    
    // Fix 0 AM / Midnight bug
    if (hr == 0) {
      hr = 12;
    } else if (hr > 12) {
      hr -= 12;
    }
    
    // Fix Minute Padding (e.g., 10:40 instead of 10:4)
    String min = time.minute == 0 ? "" : ":${time.minute.toString().padLeft(2, '0')}";
    return "$hr$min $ampm";
  }

  static String _formatDayOnly(DateTime target) {
    final now = DateTime.now();
    if (target.year == now.year && target.month == now.month && target.day == now.day) return "today";
    if (target.year == now.year && target.month == now.month && target.day == now.add(const Duration(days: 1)).day) return "tomorrow";
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return "this ${weekdays[target.weekday - 1]}";
  }

  static String _getRelativeTimeText(DateTime target, bool isDateOnly) {
    final now = DateTime.now();
    final diff = target.difference(now);
    final int roundedMinutes = (diff.inSeconds / 60).round();

    // Relative Immediacy (< 60 mins)
    if (!isDateOnly && roundedMinutes > 0 && roundedMinutes <= 60 && target.day == now.day) {
      return "in $roundedMinutes minutes";
    }

    String dayText = _formatDayOnly(target);
    if (!isDateOnly && dayText == "today" && target.hour >= 18) {
      dayText = "tonight";
    }

    if (isDateOnly) return dayText;
    return "$dayText at ${_formatTime(target, false)}";
  }

  // INTENT RESPONDERS
  static String generateCreationResponse(String title, DateTime target, bool isDateOnly, int conflictCount) {
    final timeStr = _getRelativeTimeText(target, isDateOnly);

    String base = "I've scheduled $title for $timeStr.";
    if (conflictCount > 0) {
      base += " Heads up, you have $conflictCount other task${conflictCount > 1 ? 's' : ''} around then.";
    }
    return _withCarpeDiem(base, chance: 0.15);
  }

  static String generateQueryResponse(List<Map<String, dynamic>> tasks, DateTime date) {
    if (tasks.isEmpty) {
      return _withCarpeDiem("Your schedule is completely clear for ${_formatDayOnly(date)}. Enjoy!", chance: 1.0);
    }
    
    if (tasks.length == 1) {
      final t = DateTime.fromMillisecondsSinceEpoch(tasks.first['due_date'] as int);
      final isAllDay = tasks.first['is_all_day'] == 1;
      return "You only have one thing on your agenda: ${tasks.first['title']} ${_getRelativeTimeText(t, isAllDay)}.";
    }
    
    if (tasks.length <= 3) {
      return "You have a light schedule with ${tasks.length} tasks. First up is ${tasks.first['title']}.";
    }
    
    // The Sandwich Method for heavy schedules
    final first = DateTime.fromMillisecondsSinceEpoch(tasks.first['due_date'] as int);
    final last = DateTime.fromMillisecondsSinceEpoch(tasks.last['due_date'] as int);
    final firstAllDay = tasks.first['is_all_day'] == 1;
    final lastAllDay = tasks.last['is_all_day'] == 1;
    
    return "You have ${tasks.length} tasks ${_formatDayOnly(date)}. Your day starts with ${tasks.first['title']} at ${_formatTime(first, firstAllDay)} and wraps up with ${tasks.last['title']} at ${_formatTime(last, lastAllDay)}.";
  }

  static String generateRescheduleResponse(String title, DateTime newTime, bool isDateOnly) {
    final timeStr = _getRelativeTimeText(newTime, isDateOnly);
    return "Moved $title to $timeStr.";
  }

  static String generateDeleteResponse(String title) {
    final templates = ["Done. I've removed $title.", "$title is cancelled.", "Got it, deleted $title."];
    return templates[_rand.nextInt(templates.length)];
  }

  static String generateBulkMoveResponse(int count, DateTime targetTime) {
    return "I've shifted all $count tasks to ${_formatDayOnly(targetTime)}.";
  }
}
