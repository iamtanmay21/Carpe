import 'package:flutter/material.dart';
import '../models/intent_blueprint.dart';

class _RawMatch {
  final int start;
  final int end;
  final String text;
  final DateTime? resolvedDate;
  final DateTime? resolvedEndDate;
  final RelativeDelta? relativeDelta;
  final bool isDateOnly;
  final bool isTimeOnly;
  final String? preposition;
  final TimeBlockBucket? explicitBucket;

  const _RawMatch({
    required this.start,
    required this.end,
    required this.text,
    this.resolvedDate,
    this.resolvedEndDate,
    this.relativeDelta,
    this.isDateOnly = false,
    this.isTimeOnly = false,
    this.preposition,
    this.explicitBucket,
  });
}

class OfflineNLP {
  static const _leadingPrepositions = {
    'at', 'on', 'to', 'from', 'until', 'till', 'by', 'for', 'in', 'around', 'before', 'after',
  };

  static IntentBlueprint parse(String input, {DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    // Strip seconds and milliseconds to ensure relative math (e.g., 'in 10 mins') lands on 00s
    final ref = DateTime(now.year, now.month, now.day, now.hour, now.minute);

    final normalized = _normalizeInput(input);

    final intent = _classifyIntent(normalized);
    final isBulk = intent == CommandIntent.bulkMove || intent == CommandIntent.bulkCancel;
    final statusFilter = _classifyStatus(normalized, isBulk: isBulk);

    final temporalMatches = _mergeTemporalMatches(_extractAllTemporalMatches(normalized, ref), normalized);
    final slots = _compileSlots(temporalMatches, intent, ref);
    _applySlotFallbacks(slots, intent, ref);

    var rawTitle = normalized;
    final slices = List<_RawMatch>.from(temporalMatches)
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final match in slices) {
      rawTitle = rawTitle.substring(0, match.start) + rawTitle.substring(match.end);
    }

    final polishedTitle = _cleanDanglingGrammar(_removeCommandResidue(rawTitle, intent));

    return IntentBlueprint(
      intent: intent,
      rawTextTarget: isBulk ? null : (polishedTitle.isEmpty ? null : polishedTitle),
      statusFilter: statusFilter,
      isBulk: isBulk,
      slots: slots,
      rawTranscript: input,
    );
  }

  static String _normalizeInput(String input) {
    var output = input.toLowerCase();
    output = output.replaceAll(RegExp(r'[“”]'), '"').replaceAll(RegExp(r'[’]'), "'");
    final paddingPatterns = [
      r'^\s*(?:hey|hi|hello|ok|okay)\s+(?:carpediem|carpe diem|assistant|app)\b[\s,.:;-]*',
      r'^\s*(?:hey|hi|hello|ok|okay)\b[\s,.:;-]*',
      r'^\s*(?:please|could you please|can you please|would you please)\b[\s,.:;-]*',
      r'^\s*(?:can you|could you|would you|will you)\b[\s,.:;-]*',
      r'^\s*(?:i need to|i want to|i have to|i gotta|i got to)\b[\s,.:;-]*',
      r'^\s*(?:remind me to|set a reminder to|set reminder to)\b[\s,.:;-]*',
      r'^\s*(?:tell me to|make sure i|make sure to)\b[\s,.:;-]*',
    ];

    var changed = true;
    while (changed) {
      changed = false;
      for (final pattern in paddingPatterns) {
        final next = output.replaceFirst(RegExp(pattern, caseSensitive: false), '');
        if (next != output) {
          output = next;
          changed = true;
        }
      }
    }

    output = output.replaceAll(RegExp(r'\b(?:um|uh|erm|like|just)\b'), ' ');
    output = output.replaceAll(RegExp(r'\s+'), ' ').trim();
    return output;
  }

  static CommandIntent _classifyIntent(String text) {
    // FIXED: Added "check" with a negative lookahead so it skips "checkup"
    final hasQuery = _hasAny(text, [r'show', r'list', r'what\s+is', r'read', r'agenda', r'whats', r"what's", r'what\s+are', r'what\s+do\s+i\s+have', r'when\s+(?:is|do)', r'am\s+i\s+free', r'do\s+i\s+have\s+time', r'check\b(?!\s*up)']);
    final hasReschedule = _hasAny(text, [r'move', r'shift', r'push', r'postpone', r'delay', r'reschedule', r'roll\s+over', r'bring\s+forward']);
    final hasDelete = _hasAny(text, [r'cancel', r'remove', r'drop', r'delete', r'scrap', r'clear']);
    final isBulk = _hasAny(text, [r'all', r'everything', r'all\s+(?:my\s+)?tasks?', r'entire\s+schedule', r'tasks?']);

    if (hasQuery) return CommandIntent.query;
    if (hasReschedule) return isBulk ? CommandIntent.bulkMove : CommandIntent.reschedule;
    if (hasDelete) return isBulk ? CommandIntent.bulkCancel : CommandIntent.deleteTask;
    return CommandIntent.create;
  }

  static bool _hasAny(String text, List<String> patterns) =>
      patterns.any((pattern) => RegExp('\\b$pattern\\b', caseSensitive: false).hasMatch(text));

  static String _classifyStatus(String text, {required bool isBulk}) {
    if (_hasAny(text, [r'completed', r'done', r'finished', r'past'])) return 'COMPLETED';
    if (_hasAny(text, [r'unfinished', r'pending', r'incomplete', r'remaining'])) return 'PENDING';
    return isBulk ? 'ALL' : 'PENDING';
  }

  static List<TemporalSlot> _compileSlots(List<_RawMatch> matches, CommandIntent intent, DateTime ref) {
    final slots = <TemporalSlot>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final role = _slotRole(match, intent, i);
      if (match.relativeDelta != null &&
          (intent == CommandIntent.reschedule || intent == CommandIntent.bulkMove)) {
        slots.add(TemporalSlot(
          bucket: TimeBlockBucket.none,
          delta: match.relativeDelta,
          role: SlotType.destinationTarget,
          isTimeOnly: false,
          isDateOnly: false,
        ));
        continue;
      }

      var start = match.resolvedDate!;
      
      // FIXED: If user only gives a date, expand it to bounds, and default creations to 9 AM
      if (match.isDateOnly && !match.isTimeOnly && match.resolvedEndDate == null) {
        start = _startOfDay(start); 
        if (intent == CommandIntent.create && role == SlotType.destinationTarget) {
          start = DateTime(start.year, start.month, start.day, 9, 0); 
        }
      }

      if ((intent == CommandIntent.create || intent == CommandIntent.reschedule) &&
          role == SlotType.destinationTarget &&
          !match.isDateOnly &&
          start.isBefore(ref)) {
        start = start.add(const Duration(days: 1));
      }
      final end = match.resolvedEndDate ?? (match.isTimeOnly ? _endOfTime(start) : _endOfDay(start));
      slots.add(TemporalSlot(
        exactRange: DateTimeRange(start: start, end: end),
        bucket: match.explicitBucket ?? TimeBlockBucket.fromDateTime(start),
        role: role,
        isTimeOnly: match.isTimeOnly,
        isDateOnly: match.isDateOnly,
      ));
    }
    return slots;
  }

  static SlotType _slotRole(_RawMatch match, CommandIntent intent, int index) {
    final prep = match.preposition;
    if (intent == CommandIntent.query || intent == CommandIntent.deleteTask || intent == CommandIntent.bulkCancel) {
      return SlotType.sourceFilter;
    }
    if (intent == CommandIntent.reschedule || intent == CommandIntent.bulkMove) {
      if (prep == 'from' || prep == 'for') return SlotType.sourceFilter;
      if (prep == 'to' || prep == 'until' || prep == 'till') return SlotType.destinationTarget;
      return index == 0 ? SlotType.sourceFilter : SlotType.destinationTarget;
    }
    return SlotType.destinationTarget;
  }

  static void _applySlotFallbacks(List<TemporalSlot> slots, CommandIntent intent, DateTime ref) {
    if (intent == CommandIntent.query && slots.isEmpty) {
      slots.add(TemporalSlot(
        exactRange: DateTimeRange(start: _startOfDay(ref), end: _endOfDay(ref)),
        bucket: TimeBlockBucket.none,
        role: SlotType.sourceFilter,
        isTimeOnly: false,
        isDateOnly: true,
      ));
    }
    if (intent == CommandIntent.create && slots.isEmpty) {
      slots.add(TemporalSlot(
        exactRange: DateTimeRange(start: _startOfDay(ref), end: _endOfDay(ref)),
        bucket: TimeBlockBucket.none,
        role: SlotType.destinationTarget,
        isTimeOnly: false,
        isDateOnly: true,
      ));
    }
  }

  static String _removeCommandResidue(String title, CommandIntent intent) {
    final commandPatterns = switch (intent) {
      CommandIntent.create => [r'add(?:\s+a)?(?:\s+task)?', r'schedule', r'create(?:\s+a)?(?:\s+task)?'],
      CommandIntent.query => [
        r'show(?:\s+me)?(?:\s+my)?', 
        r'list(?:\s+my)?', 
        r'read(?:\s+me)?(?:\s+my)?', 
        r"what(?:'s|s)?", 
        r'what\s+(?:is|are|do\s+i\s+have|s)', 
        r'agenda', 
        r'check\b(?:\s+my)?(?:\s+schedule|day|plans?|tasks?)?', // FIXED: Safely strips "check my schedule"
        r'all\s+(?:my\s+)?(?:schedule|plans?|tasks?)',
        r'my\s+(?:schedule|day|plans?|tasks?)', 
        r'(?:schedule|plans?|tasks?)'
      ],
      CommandIntent.reschedule || CommandIntent.bulkMove => [
        r'move', 
        r'shift', 
        r'push(?:\s+back)?', 
        r'postpone', 
        r'delay', 
        r'reschedule', 
        r'bring\s+forward', 
        r'roll\s+over', 
        r'all\s+(?:my\s+)?tasks?',
        r'tasks?', 
        r'everything'
      ],
      CommandIntent.deleteTask || CommandIntent.bulkCancel => [
        r'cancel', 
        r'remove', 
        r'drop', 
        r'delete', 
        r'scrap', 
        r'clear',
        r'all\s+(?:my\s+)?tasks?',
        r'tasks?', 
        r'everything'
      ],
    };
    var output = title;
    for (final pattern in commandPatterns) {
      output = output.replaceFirst(RegExp('^\\s*$pattern\\b', caseSensitive: false), '');
    }
    output = output.replaceFirst(RegExp(r'^\s*(?:my|the|a)\s+', caseSensitive: false), '');
    if (intent == CommandIntent.reschedule || intent == CommandIntent.bulkMove) {
      output = output.replaceFirst(RegExp(r'\s+\b(?:back|forward|earlier|later)\b\s*$', caseSensitive: false), '');
    }
    return output;
  }

  static String _cleanDanglingGrammar(String title) {
    var output = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    var changed = true;
    while (changed && output.isNotEmpty) {
      changed = false;
      output = output.replaceAll(RegExp(r'^[\s,.;:!?\-]+|[\s,.;:!?\-]+$'), '').trim();
      output = output.replaceFirst(RegExp(r"^'s\s+"), '').trim();
      final first = RegExp(r'^(\w+)\b').firstMatch(output)?.group(1)?.toLowerCase();
      if (first != null && _leadingPrepositions.contains(first)) {
        output = output.substring(first.length).trim();
        changed = true;
      }
      final last = RegExp(r'\b(\w+)$').firstMatch(output)?.group(1)?.toLowerCase();
      if (last != null && _leadingPrepositions.contains(last)) {
        output = output.substring(0, output.length - last.length).trim();
        changed = true;
      }
    }
    output = output.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (output.isEmpty) return output;
    return output[0].toUpperCase() + output.substring(1);
  }

  static List<_RawMatch> _extractAllTemporalMatches(String text, DateTime ref) {
    final matches = <_RawMatch>[];
    
    // FIXED: Forces a word boundary before the preposition so it doesn't match inside "tution" or "eat"
    const prep = r'(?:(?:\b|^)(from|to|until|till|for|by|on the|on|at|around|in)\s+)?';
    
    void add(_RawMatch match) {
      if (matches.any((m) => match.start < m.end && match.end > m.start)) return;
      matches.add(match);
    }

    final relative = RegExp(prep + r'(?:\b|^)(?:(\d+)\s*|(a|an|one)\s+)(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)\b', caseSensitive: false);
    for (final m in relative.allMatches(text)) {
      var amount = _wordNumber(m.group(2) ?? m.group(3)!);
      var unit = m.group(4)!.toLowerCase();
      if (unit.startsWith('w')) { amount *= 7; unit = 'days'; }
      else if (unit.startsWith('d')) { unit = 'days'; }
      else if (unit.startsWith('h')) { unit = 'hours'; }
      else { unit = 'minutes'; }
      final start = unit == 'days'
          ? ref.add(Duration(days: amount))
          : unit == 'hours'
              ? ref.add(Duration(hours: amount))
              : ref.add(Duration(minutes: amount));
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: start, relativeDelta: RelativeDelta(amount: amount, unit: unit, direction: RegExp(r'\b(?:forward|earlier|advance|bring)\b').hasMatch(text.substring((m.start - 24).clamp(0, text.length), m.start)) ? -1 : 1), preposition: _prep(m.group(1)), isTimeOnly: unit != 'days', isDateOnly: unit == 'days'));
    }

    final ranges = RegExp(prep + r'(this week|next week|next\s+(\d+|a|an|one)\s+days?)\b', caseSensitive: false);
    for (final m in ranges.allMatches(text)) {
      final phrase = m.group(2)!.toLowerCase();
      var start = _startOfDay(ref);
      var end = _endOfDay(ref);
      if (phrase == 'this week') end = _endOfDay(ref.add(Duration(days: 7 - ref.weekday)));
      if (phrase == 'next week') {
        start = _startOfDay(ref.add(Duration(days: 8 - ref.weekday)));
        end = _endOfDay(start.add(const Duration(days: 6)));
      }
      if (phrase.startsWith('next ') && phrase.endsWith('days')) end = _endOfDay(ref.add(Duration(days: _wordNumber(m.group(3)!))));
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: start, resolvedEndDate: end, isDateOnly: true, preposition: _prep(m.group(1))));
    }

    final dayWords = RegExp(prep + r'(today|tomorrow|yesterday)\b', caseSensitive: false);
    for (final m in dayWords.allMatches(text)) {
      final word = m.group(2)!.toLowerCase();
      final date = word == 'tomorrow' ? ref.add(const Duration(days: 1)) : word == 'yesterday' ? ref.subtract(const Duration(days: 1)) : ref;
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: date, isDateOnly: true, preposition: _prep(m.group(1))));
    }

    final weekdays = {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7};
    final weekday = RegExp(prep + r'(next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', caseSensitive: false);
    for (final m in weekday.allMatches(text)) {
      final following = text.substring(m.end, (m.end + 16).clamp(0, text.length));
      if (m.group(1) == null && RegExp(r'^\s+the\s+\d{1,2}(?:st|nd|rd|th)?\b').hasMatch(following)) continue;
      if (m.group(1) == null && RegExp(r'^\s+(?:morning|afternoon|evening|night)\s+\w+').hasMatch(following)) continue;
      final target = weekdays[m.group(3)!.toLowerCase()]!;
      var days = (target - ref.weekday) % 7;
      if (days <= 0) days += 7; 
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: DateTime(ref.year, ref.month, ref.day + days), isDateOnly: true, preposition: _prep(m.group(1))));
    }

    const monthNames = r'(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)';
    final monthMap = {'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3, 'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7, 'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'sept': 9, 'october': 10, 'oct': 10, 'november': 11, 'nov': 11, 'december': 12, 'dec': 12};
    void addMonth(RegExpMatch m, int monthIndex, int dayIndex) {
      var date = DateTime(ref.year, monthMap[m.group(monthIndex)!.toLowerCase()]!, int.parse(m.group(dayIndex)!));
      if (date.isBefore(ref.subtract(const Duration(days: 30)))) date = DateTime(date.year + 1, date.month, date.day);
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: date, isDateOnly: true, preposition: _prep(m.group(1))));
    }
    for (final m in RegExp(prep + monthNames + r'\s+(\d{1,2})(?:st|nd|rd|th)?\b', caseSensitive: false).allMatches(text)) { addMonth(m, 2, 3); }
    for (final m in RegExp(prep + r'(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?' + monthNames + r'\b', caseSensitive: false).allMatches(text)) { addMonth(m, 3, 2); }

    final time = RegExp(prep + r'(?:(?:\b|^)(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b|\b(at|around|by|from|to|until|till)\s+(\d{1,2})(?::(\d{2}))?\b)', caseSensitive: false);
    for (final m in time.allMatches(text)) {
      final prepText = _prep(m.group(1) ?? m.group(5));
      var hour = int.parse(m.group(2) ?? m.group(6)!);
      final minute = int.tryParse(m.group(3) ?? m.group(7) ?? '0') ?? 0;
      final ampm = m.group(4)?.toLowerCase().replaceAll('.', '');
      if (ampm != null) {
        if (hour < 1 || hour > 12) continue;
        if (ampm == 'pm' && hour < 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;
      } else if (hour > 23) {
        continue;
      }
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: DateTime(ref.year, ref.month, ref.day, hour, minute), isTimeOnly: true, preposition: prepText));
    }

    final namedTime = RegExp(prep + r'(tonight|this morning|morning|afternoon|evening|night)\b', caseSensitive: false);
    for (final m in namedTime.allMatches(text)) {
      final before = text.substring((m.start - 12).clamp(0, text.length), m.start);
      final after = text.substring(m.end, (m.end + 8).clamp(0, text.length));
      if (m.group(1) == null && RegExp(r'(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+$').hasMatch(before) && RegExp(r'^\s+\w+').hasMatch(after)) continue;
      final word = m.group(2)!.toLowerCase();
      var hour = 9;
      var bucket = TimeBlockBucket.morning;
      if (word.contains('afternoon')) { hour = 14; bucket = TimeBlockBucket.afternoon; }
      if (word.contains('evening')) { hour = 18; bucket = TimeBlockBucket.evening; }
      if (word.contains('tonight') || word.contains('night')) { hour = 21; bucket = TimeBlockBucket.night; }
      add(_RawMatch(start: m.start, end: m.end, text: m.group(0)!, resolvedDate: DateTime(ref.year, ref.month, ref.day, hour), isTimeOnly: true, preposition: _prep(m.group(1)), explicitBucket: bucket));
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static List<_RawMatch> _mergeTemporalMatches(List<_RawMatch> matches, String text) {
    final merged = <_RawMatch>[];
    
    bool isDirectional(String? p) => p != null && RegExp(r'^(to|until|till|from|by)$').hasMatch(p);

    for (final match in matches) {
      if (merged.isEmpty) { merged.add(match); continue; }
      final last = merged.last;
      final gap = match.start - last.end;
      final bridge = gap >= 0 && gap <= 12 ? text.substring(last.end, match.start).trim() : '';
      
      if (gap >= 0 && gap <= 12 && (bridge.isEmpty || RegExp(r'^(?:at|on|and|for|,)$').hasMatch(bridge))) {
        bool canMerge = false;
        
        if (last.isDateOnly && match.isTimeOnly) {
          canMerge = true;
        } else if (last.isTimeOnly && match.isDateOnly) {
          canMerge = true;
        } else if (last.isDateOnly && match.isDateOnly) {
          if (isDirectional(match.preposition) && match.preposition != last.preposition) {
            canMerge = false; 
          } else if (isDirectional(last.preposition) && isDirectional(match.preposition)) {
            canMerge = false; 
          } else {
            canMerge = true; 
          }
        } else if (last.isTimeOnly && match.isTimeOnly) {
          canMerge = false; 
        }

        if (canMerge) {
          final datePart = match.isDateOnly ? match.resolvedDate! : last.isDateOnly ? last.resolvedDate! : last.resolvedDate ?? match.resolvedDate!;
          final timePart = match.isTimeOnly ? match.resolvedDate! : last.isTimeOnly ? last.resolvedDate! : datePart;
          merged[merged.length - 1] = _RawMatch(
            start: last.start,
            end: match.end,
            text: text.substring(last.start, match.end),
            resolvedDate: DateTime(datePart.year, datePart.month, datePart.day, timePart.hour, timePart.minute),
            resolvedEndDate: match.resolvedEndDate ?? last.resolvedEndDate,
            relativeDelta: match.relativeDelta ?? last.relativeDelta,
            isDateOnly: last.isDateOnly || match.isDateOnly,
            isTimeOnly: last.isTimeOnly || match.isTimeOnly,
            preposition: last.preposition ?? match.preposition,
            explicitBucket: match.explicitBucket ?? last.explicitBucket,
          );
          continue; 
        }
      }
      merged.add(match);
    }
    return merged;
  }

  static String? _prep(String? prep) => prep?.replaceFirst(RegExp(r'\s+the$'), '').toLowerCase();
  static int _wordNumber(String value) => switch (value.toLowerCase()) { 'a' || 'an' || 'one' => 1, _ => int.parse(value) };
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  static DateTime _endOfTime(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute, 59);
}
