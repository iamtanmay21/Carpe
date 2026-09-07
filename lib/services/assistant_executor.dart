import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../models/intent_blueprint.dart';
import '../models/execution_result.dart';
import 'dialogue_engine.dart';
import 'offline_nlp.dart';
import 'session_manager.dart';
import 'task_resolver.dart';
import 'database_helper.dart';
import 'telecom_service.dart';
import '../data/models/task.dart';

class AssistantExecutor {
  AssistantExecutor._privateConstructor();
  static final AssistantExecutor instance = AssistantExecutor._privateConstructor();

  Future<ExecutionResult> executeVoiceCommand(
    String rawTranscript, {
    DateTime? referenceDate,
    String? quickCaptureRequestId,
  }) async {
    if (quickCaptureRequestId == null) {
      return _executeVoiceCommand(rawTranscript, referenceDate: referenceDate);
    }

    final database = DatabaseHelper.instance;
    if (!await database.claimQuickCaptureRequest(quickCaptureRequestId)) {
      final existing = await database.getQuickCaptureRequest(quickCaptureRequestId);
      final taskIds = _taskIdsFromStoredResult(existing?['result_task_ids']);
      return ExecutionResult(
        rawTranscript: rawTranscript,
        intent: CommandIntent.create,
        success: existing?['status'] == 'COMPLETED',
        feedbackMessage: existing?['result_message'] as String? ?? 'Quick capture is already being processed.',
        affectedTasks: taskIds.map((id) => <String, dynamic>{'id': id}).toList(),
        conflictingTasks: const [],
        requiresUserClarification: false,
      );
    }

    try {
      final result = await _executeVoiceCommand(rawTranscript, referenceDate: referenceDate);
      await database.completeQuickCaptureRequest(
        quickCaptureRequestId,
        status: 'COMPLETED',
        taskIds: jsonEncode(result.affectedTasks.map((task) => task['id']?.toString()).whereType<String>().toList()),
        message: result.feedbackMessage,
      );
      return result;
    } catch (_) {
      await database.completeQuickCaptureRequest(
        quickCaptureRequestId,
        status: 'FAILED',
        message: 'Quick capture could not be completed.',
      );
      rethrow;
    }
  }

  List<String> _taskIdsFromStoredResult(Object? stored) {
    if (stored is! String) return const [];
    try {
      final decoded = jsonDecode(stored);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  Future<ExecutionResult> _executeVoiceCommand(String rawTranscript, {DateTime? referenceDate}) async {
    final now = referenceDate ?? DateTime.now();
    // Strip seconds and milliseconds to guarantee alarms trigger exactly on the minute (00s)
    final ref = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final db = await DatabaseHelper.instance.database;

    IntentBlueprint blueprint;
    String? preResolvedTaskId;

    // 1. Session Manager Interception
    if (SessionManager.instance.hasActiveSession) {
      final resolution = await SessionManager.instance.processInput(rawTranscript);
      
      if (resolution.status == SessionResolutionStatus.aborted) {
        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.create, success: false,
          feedbackMessage: "Action cancelled.", affectedTasks: [], conflictingTasks: [], requiresUserClarification: false,
        );
      } else if (resolution.status == SessionResolutionStatus.completed && resolution.resolvedBlueprint != null) {
        blueprint = resolution.resolvedBlueprint!;
        // Safely cast to string in case the session manager still holds it as an int
        preResolvedTaskId = resolution.resolvedTaskId?.toString();
      } else if (resolution.status == SessionResolutionStatus.overrideWithNewCommand) {
        blueprint = OfflineNLP.parse(rawTranscript, referenceDate: ref);
      } else {
        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.create, success: false,
          feedbackMessage: "I didn't catch that.", affectedTasks: [], conflictingTasks: [], requiresUserClarification: true, clarificationPrompt: "Could you clarify?",
        );
      }
    } else {
      // Standard Parsing
      blueprint = OfflineNLP.parse(rawTranscript, referenceDate: ref);
    }

    // 2. Intent Routing & Execution
    switch (blueprint.intent) {
      
      // ------------------------------------------
      // CREATE
      // ------------------------------------------
      case CommandIntent.create:
        final title = blueprint.rawTextTarget ?? "Voice Task";
        final targetTime = _extractTargetTime(blueprint.slots) ?? ref.add(const Duration(hours: 1));
        final targetSlot = _extractTargetSlot(blueprint.slots);
        final bucket = targetSlot?.bucket ?? TimeBlockBucket.none;
        final isAllDay = targetSlot?.isDateOnly == true;

        // Conflict Detection
        final conflicts = await TaskResolver.detectConflicts(targetTime, db);

        // Database Insert (using epoch numeric string IDs for native AlarmManager request codes)
        final String newId = DateTime.now().millisecondsSinceEpoch.toString();
        await db.transaction((txn) async {
          await txn.insert('tasks', {
            'id': newId,
            'title': title,
            'due_date': targetTime.millisecondsSinceEpoch,
            'status': 'PENDING',
            'time_block_bucket': bucket.name,
            'is_all_day': isAllDay ? 1 : 0,
          });
        });

        final newTask = Task(
          id: newId,
          title: title,
          originalTranscript: rawTranscript,
          dueTimestamp: targetTime.millisecondsSinceEpoch,
          status: TaskStatusEnum.pending,
          timeBlockBucket: bucket.name,
          isAllDay: isAllDay,
        );
        await TelecomService.scheduleNativeAlarm(newTask);

        final feedback = DialogueEngine.generateCreationResponse(title, targetTime, isAllDay, conflicts.length);

        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.create, success: true, feedbackMessage: feedback,
          affectedTasks: [{'id': newId, 'title': title, 'due_date': targetTime.millisecondsSinceEpoch}],
          conflictingTasks: conflicts, requiresUserClarification: false,
        );

      // ------------------------------------------
      // QUERY
      // ------------------------------------------
      case CommandIntent.query:
        final range = _extractSourceRange(blueprint.slots) ?? DateTimeRange(start: ref, end: ref.add(const Duration(days: 1)));
        
        final String statusClause = blueprint.statusFilter == 'ALL' 
            ? "status IN ('PENDING', 'COMPLETED', 'SNOOZED')" 
            : (blueprint.statusFilter == 'COMPLETED' ? "status = 'COMPLETED'" : "status IN ('PENDING', 'SNOOZED')");

        final tasks = await db.rawQuery(
          'SELECT * FROM tasks WHERE due_date >= ? AND due_date <= ? AND $statusClause ORDER BY due_date ASC',
          [range.start.millisecondsSinceEpoch, range.end.millisecondsSinceEpoch]
        );

        final feedback = DialogueEngine.generateQueryResponse(tasks, range.start);

        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.query, success: true, feedbackMessage: feedback,
          affectedTasks: tasks, conflictingTasks: [], requiresUserClarification: false,
        );

      // ------------------------------------------
      // RESCHEDULE & DELETE
      // ------------------------------------------
      case CommandIntent.reschedule:
      case CommandIntent.deleteTask:
        List<Map<String, dynamic>> candidates = [];
        
        if (preResolvedTaskId != null) {
          candidates = await db.rawQuery('SELECT * FROM tasks WHERE id = ?', [preResolvedTaskId]);
        } else {
          candidates = await TaskResolver.findMatchingTasks(blueprint, db, ref);
        }

        if (candidates.isEmpty) {
          return ExecutionResult(
            rawTranscript: rawTranscript, intent: blueprint.intent, success: false,
            feedbackMessage: "I couldn't find a task matching ${blueprint.rawTextTarget ?? 'that'}.",
            affectedTasks: [], conflictingTasks: [], requiresUserClarification: false,
          );
        }

        // Clarification Loop Needed
        if (candidates.length > 1) {
          SessionManager.instance.startSession(blueprint, AwaitingResolution.disambiguateTask, candidates);
          return ExecutionResult(
            rawTranscript: rawTranscript, intent: blueprint.intent, success: false,
            feedbackMessage: "I found multiple tasks matching '${blueprint.rawTextTarget}'. Which one did you mean?",
            affectedTasks: candidates, conflictingTasks: [], requiresUserClarification: true, clarificationPrompt: "Which task?",
          );
        }

        final targetTask = candidates.first;
        final String taskId = targetTask['id'].toString(); // Strongly type as String
        final title = targetTask['title'] as String;

        if (blueprint.intent == CommandIntent.deleteTask) {
          await db.transaction((txn) async {
            await txn.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
          });
          await TelecomService.cancelNativeAlarm(taskId);
          return ExecutionResult(
            rawTranscript: rawTranscript, intent: CommandIntent.deleteTask, success: true,
            feedbackMessage: DialogueEngine.generateDeleteResponse(title),
            affectedTasks: [targetTask], conflictingTasks: [], requiresUserClarification: false,
          );
        }

        // Apply Reschedule Logic
        DateTime newTime = DateTime.fromMillisecondsSinceEpoch(targetTask['due_date'] as int);
        final originalTime = newTime;
        final relativeDelta = blueprint.slots.where((s) => s.delta != null).firstOrNull?.delta;
        
        if (relativeDelta != null) {
          final shift = relativeDelta.unit == 'minutes' ? Duration(minutes: relativeDelta.amount * relativeDelta.direction)
              : relativeDelta.unit == 'hours' ? Duration(hours: relativeDelta.amount * relativeDelta.direction)
              : Duration(days: relativeDelta.amount * relativeDelta.direction);
          newTime = newTime.add(shift);
        } else {
          final targetSlot = blueprint.slots.where((s) => s.role == SlotType.destinationTarget && s.exactRange != null).firstOrNull;
          if (targetSlot != null) {
            final t = targetSlot.exactRange!.start;
            if (targetSlot.isDateOnly && !targetSlot.isTimeOnly) {
              newTime = DateTime(
                t.year,
                t.month,
                t.day,
                originalTime.hour,
                originalTime.minute,
              );
            } else {
              newTime = t;
            }
          }
        }

        newTime = _bumpPastTimeToNextBubble(newTime, DateTime.now());
        newTime = await _findOpenThirtyMinuteBubble(db, newTime, excludeTaskId: taskId);
        final bool isDateOnlyTarget = (targetTask['is_all_day'] as int?) == 1;

        final conflicts = await TaskResolver.detectConflicts(newTime, db, excludeTaskId: taskId);

        await db.transaction((txn) async {
          await txn.update('tasks', {'due_date': newTime.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [taskId]);
        });

        final updatedRows = await db.rawQuery('SELECT * FROM tasks WHERE id = ?', [taskId]);
        if (updatedRows.isNotEmpty) {
          final updatedTask = Task.fromMap(updatedRows.first);
          await TelecomService.scheduleNativeAlarm(updatedTask);
        }

        final feedback = DialogueEngine.generateRescheduleResponse(title, newTime, isDateOnlyTarget);

        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.reschedule, success: true, feedbackMessage: feedback,
          affectedTasks: [targetTask], conflictingTasks: conflicts, requiresUserClarification: false,
        );

      // ------------------------------------------
      // BULK MOVE
      // ------------------------------------------
      case CommandIntent.bulkMove:
        final range = _extractSourceRange(blueprint.slots) ?? DateTimeRange(start: ref, end: ref.add(const Duration(days: 1)));
        final targetTime = _extractTargetTime(blueprint.slots) ?? ref.add(const Duration(days: 1));
        final bucket = _extractBucket(blueprint.slots);

        final String statusClause = blueprint.statusFilter == 'ALL' 
            ? "status IN ('PENDING', 'COMPLETED', 'SNOOZED')" : "status IN ('PENDING', 'SNOOZED')";

        final tasks = await db.rawQuery(
          'SELECT * FROM tasks WHERE due_date >= ? AND due_date <= ? AND $statusClause',
          [range.start.millisecondsSinceEpoch, range.end.millisecondsSinceEpoch]
        );

        if (tasks.isEmpty) {
          return ExecutionResult(
            rawTranscript: rawTranscript, intent: CommandIntent.bulkMove, success: false,
            feedbackMessage: "You have no tasks to move in that time frame.", affectedTasks: [], conflictingTasks: [], requiresUserClarification: false,
          );
        }

        final cascaded = TaskResolver.cascadeBulkMove(tasks, targetTime, bucket);
        final resolvedMoves = <Map<String, dynamic>>[];
        final reservedDueTimestamps = <int>{};
        for (final task in cascaded) {
          final resolvedTask = Map<String, dynamic>.from(task);
          var resolvedTime = DateTime.fromMillisecondsSinceEpoch(resolvedTask['due_date'] as int);
          resolvedTime = _bumpPastTimeToNextBubble(resolvedTime, DateTime.now());
          resolvedTime = await _findOpenThirtyMinuteBubble(
            db,
            resolvedTime,
            excludeTaskId: resolvedTask['id'].toString(),
            reservedDueTimestamps: reservedDueTimestamps,
          );
          resolvedTask['due_date'] = resolvedTime.millisecondsSinceEpoch;
          reservedDueTimestamps.add(resolvedTask['due_date'] as int);
          resolvedMoves.add(resolvedTask);
        }
        
        await db.transaction((txn) async {
          for (var t in resolvedMoves) {
            await txn.update(
              'tasks', 
              {'due_date': t['due_date'], 'time_block_bucket': t['time_block_bucket']}, 
              where: 'id = ?', 
              whereArgs: [t['id'].toString()] // Strongly type as String
            );
          }
        });

        // Simple conflict check: just seeing if destination already has tasks
        final destConflicts = await TaskResolver.detectConflicts(targetTime, db);

        final feedback = DialogueEngine.generateBulkMoveResponse(resolvedMoves.length, targetTime);
        
        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.bulkMove, success: true, feedbackMessage: feedback,
          affectedTasks: resolvedMoves, conflictingTasks: destConflicts, requiresUserClarification: false,
        );

      case CommandIntent.bulkCancel:
        return ExecutionResult(
          rawTranscript: rawTranscript, intent: CommandIntent.bulkCancel, success: false,
          feedbackMessage: "Bulk cancellation is disabled for safety.", affectedTasks: [], conflictingTasks: [], requiresUserClarification: false,
        );
    }
  }

  DateTime _bumpPastTimeToNextBubble(DateTime targetTime, DateTime now) {
    if (targetTime.isAfter(now)) return targetTime;

    final nextBubbleMinute = ((now.minute ~/ 30) + 1) * 30;
    return DateTime(now.year, now.month, now.day, now.hour, nextBubbleMinute);
  }

  Future<DateTime> _findOpenThirtyMinuteBubble(
    DatabaseExecutor db,
    DateTime targetTime, {
    String? excludeTaskId,
    Set<int>? reservedDueTimestamps,
  }) async {
    var candidate = targetTime;

    while (await _hasThirtyMinuteBubbleCollision(
      db,
      candidate,
      excludeTaskId: excludeTaskId,
      reservedDueTimestamps: reservedDueTimestamps,
    )) {
      candidate = candidate.add(const Duration(minutes: 30));
    }

    return candidate;
  }

  Future<bool> _hasThirtyMinuteBubbleCollision(
    DatabaseExecutor db,
    DateTime targetTime, {
    String? excludeTaskId,
    Set<int>? reservedDueTimestamps,
  }) async {
    final windowStart = targetTime.millisecondsSinceEpoch;
    final windowEnd = targetTime.add(const Duration(minutes: 30)).millisecondsSinceEpoch;

    final hasReservedCollision = reservedDueTimestamps?.any(
          (timestamp) => timestamp >= windowStart && timestamp < windowEnd,
        ) ??
        false;
    if (hasReservedCollision) return true;

    var sql = '''
      SELECT id FROM tasks
      WHERE status IN ('PENDING', 'SNOOZED')
        AND due_date >= ?
        AND due_date < ?
    ''';
    final args = <Object>[windowStart, windowEnd];

    if (excludeTaskId != null) {
      sql += ' AND id != ?';
      args.add(excludeTaskId);
    }

    final collisions = await db.rawQuery(sql, args);
    return collisions.isNotEmpty;
  }

  // --- Helpers ---
  TemporalSlot? _extractTargetSlot(List<TemporalSlot> slots) {
    return slots
        .where((s) => s.role == SlotType.destinationTarget && s.exactRange != null)
        .firstOrNull;
  }

  DateTime? _extractTargetTime(List<TemporalSlot> slots) {
    return _extractTargetSlot(slots)?.exactRange?.start;
  }

  DateTimeRange? _extractSourceRange(List<TemporalSlot> slots) {
    return slots.where((s) => s.role == SlotType.sourceFilter && s.exactRange != null)
        .firstOrNull?.exactRange;
  }
  
  TimeBlockBucket _extractBucket(List<TemporalSlot> slots) {
    return slots.where((s) => s.role == SlotType.destinationTarget)
        .firstOrNull?.bucket ?? TimeBlockBucket.none;
  }
}
