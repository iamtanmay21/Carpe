// Removed dart:math
import 'package:sqflite/sqflite.dart';
import '../models/intent_blueprint.dart';
import 'database_helper.dart';

class TaskResolver {
  
  /// 1. Candidate Entity Matching (Trigrams & Contextual Sifting)
  static Future<List<Map<String, dynamic>>> findMatchingTasks(
      IntentBlueprint blueprint, Database db, DateTime referenceDate) async {
    
    if (blueprint.rawTextTarget == null || blueprint.rawTextTarget!.isEmpty) {
      return [];
    }

    final String target = blueprint.rawTextTarget!.toLowerCase();
    
    // 1a. Fetch candidate IDs using FTS5 (Now strongly typed as String for UUIDs)
    final List<String> candidateIds = await DatabaseHelper.instance.searchTaskIdsByFts(target);
    
    if (candidateIds.isEmpty) {
      return [];
    }

    // 1b. Fetch full task rows for the candidates
    final placeholders = List.filled(candidateIds.length, '?').join(',');
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT * FROM tasks WHERE id IN ($placeholders)',
      candidateIds,
    );

    // 1c. Calculate Trigram Similarity and filter
    final List<Map<String, dynamic>> scoredCandidates = [];
    for (var row in rows) {
      final String title = (row['title'] as String).toLowerCase();
      final double score = _calculateTrigramSimilarity(target, title);
      
      if (score >= 0.45) {
        final mutableRow = Map<String, dynamic>.from(row);
        mutableRow['similarityScore'] = score;
        scoredCandidates.add(mutableRow);
      }
    }

    if (scoredCandidates.isEmpty) return [];

    // 1d. Contextual Sifting Filter
    // Sort by score (desc), then overdue priority, then chronological proximity
    scoredCandidates.sort((a, b) {
      final scoreA = a['similarityScore'] as double;
      final scoreB = b['similarityScore'] as double;
      
      if ((scoreA - scoreB).abs() > 0.05) {
        return scoreB.compareTo(scoreA); // Highest score first
      }

      // Priority 1: Overdue PENDING tasks
      final dateA = DateTime.fromMillisecondsSinceEpoch(a['due_date'] as int);
      final dateB = DateTime.fromMillisecondsSinceEpoch(b['due_date'] as int);
      final isOverdueA = dateA.isBefore(referenceDate) && a['status'] == 'PENDING';
      final isOverdueB = dateB.isBefore(referenceDate) && b['status'] == 'PENDING';
      
      if (isOverdueA && !isOverdueB) return -1;
      if (isOverdueB && !isOverdueA) return 1;

      // Priority 2: Closest chronologically to reference date
      final diffA = (dateA.millisecondsSinceEpoch - referenceDate.millisecondsSinceEpoch).abs();
      final diffB = (dateB.millisecondsSinceEpoch - referenceDate.millisecondsSinceEpoch).abs();
      
      return diffA.compareTo(diffB);
    });

    // Priority 3: Check for high-score week-level ambiguities
    final topScore = scoredCandidates.first['similarityScore'] as double;
    final topCandidates = scoredCandidates.where((c) => (topScore - (c['similarityScore'] as double)).abs() <= 0.05).toList();

    if (topCandidates.length > 1) {
      final firstDate = DateTime.fromMillisecondsSinceEpoch(topCandidates.first['due_date'] as int);
      final sameWeekCandidates = topCandidates.where((c) {
        final d = DateTime.fromMillisecondsSinceEpoch(c['due_date'] as int);
        // Basic same-week check (within 7 days)
        return d.difference(firstDate).inDays.abs() <= 7;
      }).toList();

      if (sameWeekCandidates.length > 1) {
        // Return multiple for UI/Voice disambiguation
        return sameWeekCandidates;
      }
    }

    // Return the single best matched task
    return [scoredCandidates.first];
  }

  /// Calculates Jaccard similarity of 3-character sequences (trigrams)
  static double _calculateTrigramSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.length < 3 || s2.length < 3) {
      return s1.contains(s2) || s2.contains(s1) ? 0.6 : 0.0;
    }

    Set<String> getTrigrams(String str) {
      Set<String> trigrams = {};
      for (int i = 0; i <= str.length - 3; i++) {
        trigrams.add(str.substring(i, i + 3));
      }
      return trigrams;
    }

    final t1 = getTrigrams(s1);
    final t2 = getTrigrams(s2);
    
    if (t1.isEmpty || t2.isEmpty) return 0.0;

    final intersectionSize = t1.intersection(t2).length;
    final unionSize = t1.length + t2.length - intersectionSize;
    
    return intersectionSize / unionSize;
  }

  /// 2. Positional Logic Router with Database Validation
  static Future<List<TemporalSlot>> resolveRescheduleSlots(
      IntentBlueprint blueprint, Map<String, dynamic> candidateTask) async {
    
    if (blueprint.slots.length != 2) return blueprint.slots;

    final slot1 = blueprint.slots[0];
    final slot2 = blueprint.slots[1];

    if (slot1.exactRange == null || slot2.exactRange == null) return blueprint.slots;

    final taskTime = candidateTask['due_date'] as int;
    final s1Midpoint = (slot1.exactRange!.start.millisecondsSinceEpoch + slot1.exactRange!.end.millisecondsSinceEpoch) ~/ 2;
    final s2Midpoint = (slot2.exactRange!.start.millisecondsSinceEpoch + slot2.exactRange!.end.millisecondsSinceEpoch) ~/ 2;

    // Check if task exists near Slot 1 or Slot 2 (using a generous 12-hour window for daily loose matches)
    const windowMs = 12 * 60 * 60 * 1000; 
    
    final matchNearS1 = (taskTime - s1Midpoint).abs() < windowMs;
    final matchNearS2 = (taskTime - s2Midpoint).abs() < windowMs;

    if (matchNearS1 && !matchNearS2) {
      // Slot 1 is source, Slot 2 is destination
      return [
        _cloneSlotWithRole(slot1, SlotType.sourceFilter),
        _cloneSlotWithRole(slot2, SlotType.destinationTarget)
      ];
    } else if (matchNearS2 && !matchNearS1) {
      // Inversion Check: Slot 2 is source, Slot 1 is destination
      return [
        _cloneSlotWithRole(slot2, SlotType.sourceFilter),
        _cloneSlotWithRole(slot1, SlotType.destinationTarget)
      ];
    }

    // Both or neither match closely -> leave as parsed (often requires clarification)
    return blueprint.slots;
  }

  static TemporalSlot _cloneSlotWithRole(TemporalSlot slot, SlotType newRole) {
    return TemporalSlot(
      exactRange: slot.exactRange,
      bucket: slot.bucket,
      delta: slot.delta,
      role: newRole,
      isTimeOnly: slot.isTimeOnly,
      isDateOnly: slot.isDateOnly
    );
  }

  /// 3. Schedule Conflict & Overlap Detection
  static Future<List<Map<String, dynamic>>> detectConflicts(
      DateTime targetTime, Database db, {String? excludeTaskId}) async {
    
    // +/- 30-Minute Guard Band Rule
    const int guardBandMs = 30 * 60 * 1000;
    final int targetMs = targetTime.millisecondsSinceEpoch;
    
    final int windowStart = targetMs - guardBandMs;
    final int windowEnd = targetMs + guardBandMs;

    String sql = 'SELECT * FROM tasks WHERE status = ? AND due_date > ? AND due_date < ?';
    List<dynamic> args = ['PENDING', windowStart, windowEnd];

    if (excludeTaskId != null) {
      sql += ' AND id != ?';
      args.add(excludeTaskId);
    }

    return await db.rawQuery(sql, args);
  }

  /// 4. Bulk Move Cascader Algorithm
  static List<Map<String, dynamic>> cascadeBulkMove(
      List<Map<String, dynamic>> tasksToMove, DateTime targetDate, TimeBlockBucket? bucket) {
    
    final List<Map<String, dynamic>> cascadedTasks = [];
    
    int allDayOffsetMinutes = 0;
    int baseHour = 9; // Default morning fallback
    
    if (bucket != null && bucket != TimeBlockBucket.none) {
      baseHour = bucket.getRange(targetDate)?.start.hour ?? 9;
    }

    for (var task in tasksToMove) {
      final isAllDay = (task['is_all_day'] as int) == 1;
      final origDate = DateTime.fromMillisecondsSinceEpoch(task['due_date'] as int);
      
      DateTime newTime;
      
      if (!isAllDay) {
        // Time preservation for specific-time tasks
        newTime = DateTime(
          targetDate.year, targetDate.month, targetDate.day, 
          origDate.hour, origDate.minute
        );
      } else {
        // Cascade all-day tasks starting at the bucket start hour with +1 min increments
        newTime = DateTime(
          targetDate.year, targetDate.month, targetDate.day, 
          baseHour, allDayOffsetMinutes
        );
        allDayOffsetMinutes++;
      }

      final mutableTask = Map<String, dynamic>.from(task);
      mutableTask['due_date'] = newTime.millisecondsSinceEpoch;
      mutableTask['time_block_bucket'] = bucket?.name ?? task['time_block_bucket'];
      
      cascadedTasks.add(mutableTask);
    }

    return cascadedTasks;
  }
}
