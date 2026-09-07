import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart'; // <-- ADDED: Fixes the 'Sqflite' getter error
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/task.dart'; // Ensure this points to your updated Task model

class DatabaseHelper {
  DatabaseHelper._privateConstructor();

  /// Allows focused database tests to use an isolated factory and path.
  DatabaseHelper.forTesting({required DatabaseFactory factory, required String path})
      : _factoryOverride = factory,
        _pathOverride = path;
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  final DatabaseFactory? _factoryOverride;
  final String? _pathOverride;
  Future<Database>? _databaseFuture;

  /// A single-flight open prevents callers in one Dart engine racing to open
  /// the same file and configure separate connections.
  Future<Database> get database {
    return _databaseFuture ??= _initDatabase();
  }

  Future<Database> _initDatabase() async {
    String dbPath = _pathOverride ?? 'carpe_diem.db';
    final factory = _factoryOverride ?? databaseFactory;
    if (kIsWeb) {
      // Browser builds have no platform sqflite implementation.
      dbPath = _pathOverride ?? dbPath;
    } else {
      // Android and iOS must retain sqflite's platform factory. FFI is only
      // needed by desktop hosts, where sqflite has no native implementation.
      if (_factoryOverride == null &&
          (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS)) {
        sqfliteFfiInit();
        return _openDatabase(databaseFactoryFfi, _pathOverride ?? await _databasePath());
      }
      dbPath = _pathOverride ?? await _databasePath();
    }
    return _openDatabase(kIsWeb ? databaseFactoryFfiWeb : factory, dbPath);
  }

  Future<String> _databasePath() async {
    final io.Directory appDocDir = await getApplicationDocumentsDirectory();
    return join(appDocDir.path, 'carpe_diem.db');
  }

  Future<Database> _openDatabase(DatabaseFactory factory, String dbPath) async {
    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA busy_timeout=5000');
    await db.execute('PRAGMA foreign_keys=ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    // Expanded schema to support UI parameters (audioPath, routineDays, etc.)
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        due_date INTEGER,
        status TEXT DEFAULT 'PENDING',
        is_all_day INTEGER DEFAULT 0,
        time_block_bucket TEXT DEFAULT 'none',
        audioPath TEXT,
        routineDays TEXT,
        contactName TEXT,
        contact_number TEXT,
        voice_note_path TEXT,
        is_non_priority INTEGER DEFAULT 0,
        originalTranscript TEXT
      )
    ''');

    // FTS5 Virtual Table for Voice Search
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
        title,
        content='tasks',
        content_rowid='rowid',
        tokenize='porter unicode61'
      )
    ''');

    // Sync Triggers
    await db.execute('''
      CREATE TRIGGER tasks_ai AFTER INSERT ON tasks
      BEGIN
        INSERT INTO tasks_fts(rowid, title) VALUES (new.rowid, new.title);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER tasks_ad AFTER DELETE ON tasks
      BEGIN
        INSERT INTO tasks_fts(tasks_fts, rowid, title) VALUES('delete', old.rowid, old.title);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER tasks_au AFTER UPDATE OF title ON tasks
      BEGIN
        INSERT INTO tasks_fts(tasks_fts, rowid, title) VALUES('delete', old.rowid, old.title);
        INSERT INTO tasks_fts(rowid, title) VALUES (new.rowid, new.title);
      END;
    ''');
    await _createQuickCaptureRequestsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tasks ADD COLUMN contact_number TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN voice_note_path TEXT');
      await db.execute(
        'ALTER TABLE tasks ADD COLUMN is_non_priority INTEGER DEFAULT 0',
      );
      await db.execute(
        'UPDATE tasks SET contact_number = contactNumber '
        'WHERE contact_number IS NULL',
      );
    }
    if (oldVersion < 3) {
      // Limit FTS synchronization to title changes to avoid Android SQLite crashes.
      await db.execute('DROP TRIGGER IF EXISTS tasks_au');
      await db.execute('''
        CREATE TRIGGER tasks_au AFTER UPDATE OF title ON tasks
        BEGIN
          INSERT INTO tasks_fts(tasks_fts, rowid, title) VALUES('delete', old.rowid, old.title);
          INSERT INTO tasks_fts(rowid, title) VALUES (new.rowid, new.title);
        END;
      ''');
    }
    if (oldVersion < 4) {
      await _createQuickCaptureRequestsTable(db);
    }
  }

  Future<void> _createQuickCaptureRequestsTable(DatabaseExecutor db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS quick_capture_requests (
        request_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        result_task_ids TEXT,
        result_message TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');
  }

  /// Atomically claims an idempotency key for processing.
  ///
  /// A retryable outcome can be claimed again, while processing, completed,
  /// and terminally failed requests remain owned by their existing outcome.
  Future<bool> claimQuickCaptureRequest(String requestId) async {
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'quick_capture_requests',
        columns: const ['status'],
        where: 'request_id = ?',
        whereArgs: [requestId],
      );
      if (existing.isEmpty) {
        await txn.insert('quick_capture_requests', {
          'request_id': requestId,
          'status': 'PROCESSING',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      }

      if (existing.single['status'] != 'RETRYABLE') return false;
      return await txn.update(
            'quick_capture_requests',
            {'status': 'PROCESSING', 'completed_at': null},
            where: 'request_id = ? AND status = ?',
            whereArgs: [requestId, 'RETRYABLE'],
          ) ==
          1;
    });
  }

  Future<Map<String, Object?>?> getQuickCaptureRequest(String requestId) async {
    final rows = await (await database).query('quick_capture_requests', where: 'request_id = ?', whereArgs: [requestId]);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> completeQuickCaptureRequest(
    String requestId, {
    required String status,
    String? taskIds,
    required String message,
  }) async {
    await (await database).update('quick_capture_requests', {
      'status': status,
      'result_task_ids': taskIds,
      'result_message': message,
      'completed_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'request_id = ?', whereArgs: [requestId]);
  }

  // Section divider
  // UI CRUD METHODS (Fixes empty dashboard & manual creation)
  // Section divider

  Future<List<Task>> getAllTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('tasks', orderBy: 'due_date ASC');
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert('tasks', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTaskStatus(String id, String status) async {
    final db = await database;
    await db.update('tasks', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // Section divider
  // DASHBOARD STATS METHODS
  // Section divider

  Future<int> getCompletedCount() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) FROM tasks WHERE status = 'COMPLETED'");
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getMissedCount() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) FROM tasks WHERE status = 'MISSED'");
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> getSuccessRate() async {
    final completed = await getCompletedCount();
    final missed = await getMissedCount();
    final total = completed + missed;
    return total == 0 ? 0.0 : (completed / total) * 100;
  }

  // Section divider
  // VOICE ASSISTANT FTS5 ENGINE
  // Section divider

  Future<List<String>> searchTaskIdsByFts(String query) async {
    final db = await database;
    final searchPattern = '"$query"*';

    final List<Map<String, dynamic>> results = await db.rawQuery(
      'SELECT id FROM tasks WHERE rowid IN (SELECT rowid FROM tasks_fts WHERE title MATCH ?) LIMIT 10',
      [searchPattern]
    );

    return results.map((row) => row['id'] as String).toList();
  }
}
