/// Purely offline, regex-based NLP parser.
/// No network calls, no cloud APIs — works 100% on-device.
library;

class TaskData {
  final String title;
  final DateTime? dueDateTime;
  final String originalTranscript;

  const TaskData({
    required this.title,
    required this.originalTranscript,
    this.dueDateTime,
  });

  @override
  String toString() => 'TaskData(title: "$title", due: $dueDateTime)';
}

class NlpParser {
  NlpParser._();

  // ─── Wake-word stripping ────────────────────────────────────────────────
  static final _wakeWordRegex = RegExp(
    r'^(remind\s+me\s+to|remind\s+me|set\s+a\s+task\s+to|add\s+to\s+do|carpe)\s+',
    caseSensitive: false,
  );

  // ─── Time extraction ────────────────────────────────────────────────────
  // Matches: "3pm", "3 pm", "3:30pm", "3:30 p.m.", "15:00"
  static final _timeRegex = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?:\s|$)',
    caseSensitive: false,
  );

  // ─── Date extraction ────────────────────────────────────────────────────
  static final _todayRegex = RegExp(r'\btoday\b', caseSensitive: false);
  static final _tonightRegex = RegExp(r'\btonight\b', caseSensitive: false);
  static final _tomorrowRegex = RegExp(r'\btomorrow\b', caseSensitive: false);
  static final _weekdayRegex = RegExp(
    r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    caseSensitive: false,
  );

  // ─── Preposition noise ──────────────────────────────────────────────────
  static final _prepRegex = RegExp(
    r'\b(at|on|by|for|in|the|next)\b\s*',
    caseSensitive: false,
  );

  /// Main entry point.
  static TaskData parseTranscript(String input) {
    String text = input.trim();
    final originalTranscript = text;

    // 1. Strip wake words
    text = text.replaceFirst(_wakeWordRegex, '');

    // 2. Extract date
    DateTime? date;
    bool tonightFlag = false;

    if (_tonightRegex.hasMatch(text)) {
      date = _today();
      tonightFlag = true;
      text = text.replaceAll(_tonightRegex, '');
    } else if (_todayRegex.hasMatch(text)) {
      date = _today();
      text = text.replaceAll(_todayRegex, '');
    } else if (_tomorrowRegex.hasMatch(text)) {
      date = _today().add(const Duration(days: 1));
      text = text.replaceAll(_tomorrowRegex, '');
    } else {
      final weekdayMatch = _weekdayRegex.firstMatch(text);
      if (weekdayMatch != null) {
        date = _nextWeekday(_weekdayIndex(weekdayMatch.group(1)!));
        text = text.replaceAll(_weekdayRegex, '');
      }
    }

    // Default to today if no date found
    date ??= _today();

    // 3. Extract time
    int? hour;
    int? minute;
    final timeMatch = _timeRegex.firstMatch(text);

    if (timeMatch != null) {
      hour = int.parse(timeMatch.group(1)!);
      minute = timeMatch.group(2) != null ? int.parse(timeMatch.group(2)!) : 0;
      final meridiem = timeMatch.group(3)?.toLowerCase().replaceAll('.', '');

      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      text = text.replaceFirst(timeMatch.group(0)!, '');
    } else if (tonightFlag) {
      // "tonight" with no explicit time → 20:00
      hour = 20;
      minute = 0;
    }

    // 4. Build final DateTime
    DateTime? dueDateTime;
    if (hour != null) {
      dueDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute ?? 0,
      );
    } else {
      // No time specified — keep the date only (midnight)
      dueDateTime = DateTime(date.year, date.month, date.day);
    }

    // 5. Clean up title
    String title = text
        .replaceAll(_prepRegex, ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (title.isEmpty) title = originalTranscript.trim();

    // Capitalise first letter
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    return TaskData(
      title: title,
      dueDateTime: dueDateTime,
      originalTranscript: originalTranscript,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _nextWeekday(int targetWeekday) {
    final now = DateTime.now();
    int daysAhead = targetWeekday - now.weekday;
    if (daysAhead <= 0) daysAhead += 7;
    return DateTime(now.year, now.month, now.day + daysAhead);
  }

  static int _weekdayIndex(String name) {
    switch (name.toLowerCase()) {
      case 'monday':
        return DateTime.monday;
      case 'tuesday':
        return DateTime.tuesday;
      case 'wednesday':
        return DateTime.wednesday;
      case 'thursday':
        return DateTime.thursday;
      case 'friday':
        return DateTime.friday;
      case 'saturday':
        return DateTime.saturday;
      case 'sunday':
        return DateTime.sunday;
      default:
        return DateTime.monday;
    }
  }
}
