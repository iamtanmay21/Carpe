import 'package:flutter/material.dart';

enum CommandIntent { 
  create, 
  query, 
  reschedule, 
  deleteTask, 
  bulkMove, 
  bulkCancel 
}

enum TimeBlockBucket {
  morning,
  afternoon,
  evening,
  night,
  none;

  /// Returns the exact DateTimeRange for this bucket on a given base date.
  DateTimeRange? getRange(DateTime baseDate) {
    final y = baseDate.year;
    final m = baseDate.month;
    final d = baseDate.day;
    
    switch (this) {
      case TimeBlockBucket.morning:
        return DateTimeRange(
            start: DateTime(y, m, d, 6, 0), 
            end: DateTime(y, m, d, 11, 59, 59, 999));
      case TimeBlockBucket.afternoon:
        return DateTimeRange(
            start: DateTime(y, m, d, 12, 0), 
            end: DateTime(y, m, d, 16, 59, 59, 999));
      case TimeBlockBucket.evening:
        return DateTimeRange(
            start: DateTime(y, m, d, 17, 0), 
            end: DateTime(y, m, d, 20, 59, 59, 999));
      case TimeBlockBucket.night:
        return DateTimeRange(
            start: DateTime(y, m, d, 21, 0), 
            end: DateTime(y, m, d, 23, 59, 59, 999));
      case TimeBlockBucket.none:
        return null;
    }
  }

  /// Evaluates an exact DateTime to determine its TimeBlockBucket.
  static TimeBlockBucket fromDateTime(DateTime dt) {
    final h = dt.hour;
    if (h >= 6 && h < 12) return TimeBlockBucket.morning;
    if (h >= 12 && h < 17) return TimeBlockBucket.afternoon;
    if (h >= 17 && h < 21) return TimeBlockBucket.evening;
    if (h >= 21 && h <= 23) return TimeBlockBucket.night;
    return TimeBlockBucket.none;
  }
}

enum SlotType { 
  sourceFilter, 
  destinationTarget, 
  neutral 
}

/// Helper model for relative math (e.g. "push back by 2 hours")
class RelativeDelta {
  final int amount;
  final String unit; // e.g., 'minutes', 'hours', 'days'
  final int direction; // e.g., 1 for forward, -1 for backward

  const RelativeDelta({
    required this.amount,
    required this.unit,
    required this.direction,
  });
}

class TemporalSlot {
  final DateTimeRange? exactRange;
  final TimeBlockBucket bucket;
  final RelativeDelta? delta;
  final SlotType role;
  final bool isTimeOnly;
  final bool isDateOnly;

  const TemporalSlot({
    this.exactRange,
    required this.bucket,
    this.delta,
    required this.role,
    required this.isTimeOnly,
    required this.isDateOnly,
  });
}

class IntentBlueprint {
  final CommandIntent intent;
  final String? rawTextTarget;
  final String? statusFilter;
  final bool isBulk;
  final List<TemporalSlot> slots;
  final String rawTranscript;

  const IntentBlueprint({
    required this.intent,
    this.rawTextTarget,
    this.statusFilter,
    required this.isBulk,
    required this.slots,
    required this.rawTranscript,
  });
}
