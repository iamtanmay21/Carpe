import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' as io;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart'; // <-- ADDED: Fixes the 'Sqflite' getter error
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/task.dart'; // Ensure this points to your updated Task model

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath = 'carpe_diem.db';
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else {
      // 1. Optimize startup: Only invoke FFI on supported platforms to prevent long load times
      if (io.Platform.isAndroid || io.Platform.isWindows || io.Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // 2. UNIFIED DB NAME: 'carpe_diem.db'
      // This perfectly matches the Kotlin native alarm system and the UI expectations.
      final io.Directory appDocDir = await getApplicationDocumentsDirectory();
      dbPath = join(appDocDir.path, 'carpe_diem.db');
    }

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    // Temporary diagnostics: retain these logs until Flutter and native paths
    // and connection-level SQLite settings have been compared on a device.
    debugPrint('[DatabaseDiagnostics][Flutter] path=${db.path}');
    debugPrint(
      '[DatabaseDiagnostics][Flutter] journal_mode='
      '${await db.rawQuery('PRAGMA journal_mode;')}',
    );
    debugPrint(
      '[DatabaseDiagnostics][Flutter] busy_timeout='
      '${await db.rawQuery('PRAGMA busy_timeout;')}',
    );

    return db;
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
