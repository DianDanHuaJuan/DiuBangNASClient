/// 文件输入：本地数据库初始化配置、表结构版本
/// 文件职责：提供任务、备份计划等结构化数据持久化入口
/// 文件对外接口：AppDatabase
/// 文件包含：AppDatabase
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static Database? _database;
  static const String _dbName = 'nas_client.db';
  static const int _dbVersion = 4;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transfer_tasks (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        source_path TEXT NOT NULL,
        target_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        progress REAL DEFAULT 0,
        status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE backup_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_path TEXT NOT NULL,
        target_path TEXT NOT NULL,
        mode TEXT NOT NULL,
        server_id TEXT,
        root_id TEXT DEFAULT 'fs',
        schedule_type TEXT,
        schedule_time TEXT,
        schedule_days TEXT,
        schedule_day_of_month INTEGER,
        schedule_once_at TEXT,
        requires_wifi INTEGER DEFAULT 0,
        requires_charging INTEGER DEFAULT 0,
        include_images INTEGER DEFAULT 1,
        include_videos INTEGER DEFAULT 1,
        enabled INTEGER DEFAULT 1,
        last_run_at TEXT,
        schedule_status TEXT DEFAULT 'unscheduled',
        schedule_error TEXT,
        scheduled_run_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE backup_runs (
        id TEXT PRIMARY KEY,
        plan_id TEXT,
        trigger_type TEXT NOT NULL,
        status TEXT NOT NULL,
        scanned_count INTEGER DEFAULT 0,
        queued_count INTEGER DEFAULT 0,
        skipped_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE backup_plan_items (
        plan_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        selected_at TEXT NOT NULL,
        PRIMARY KEY (plan_id, source_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE backup_asset_state (
        server_id TEXT NOT NULL,
        root_id TEXT NOT NULL,
        source_fingerprint TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        modified_ms INTEGER NOT NULL,
        mime_type TEXT,
        content_hash TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_backup_asset_state_server_root
      ON backup_asset_state(server_id, root_id, updated_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE relay_records (
        id TEXT PRIMARY KEY,
        sender_device_id TEXT NOT NULL,
        receiver_device_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeToV3(db);
    }
    if (oldVersion < 4) {
      await _upgradeToV4(db);
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    await _ensureBackupPlanColumn(db, 'server_id', 'TEXT');
    await _ensureBackupPlanColumn(db, 'root_id', "TEXT DEFAULT 'fs'");
    await _ensureBackupPlanColumn(db, 'schedule_days', 'TEXT');
    await _ensureBackupPlanColumn(db, 'requires_wifi', 'INTEGER DEFAULT 0');
    await _ensureBackupPlanColumn(db, 'requires_charging', 'INTEGER DEFAULT 0');
    await _ensureBackupPlanColumn(db, 'include_images', 'INTEGER DEFAULT 1');
    await _ensureBackupPlanColumn(db, 'include_videos', 'INTEGER DEFAULT 1');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_runs (
        id TEXT PRIMARY KEY,
        plan_id TEXT,
        trigger_type TEXT NOT NULL,
        status TEXT NOT NULL,
        scanned_count INTEGER DEFAULT 0,
        queued_count INTEGER DEFAULT 0,
        skipped_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_plan_items (
        plan_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        selected_at TEXT NOT NULL,
        PRIMARY KEY (plan_id, source_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_asset_state (
        server_id TEXT NOT NULL,
        root_id TEXT NOT NULL,
        source_fingerprint TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        modified_ms INTEGER NOT NULL,
        mime_type TEXT,
        content_hash TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_backup_asset_state_server_root
      ON backup_asset_state(server_id, root_id, updated_at DESC)
    ''');
  }

  Future<void> _upgradeToV3(Database db) async {
    await _ensureBackupPlanColumn(db, 'schedule_day_of_month', 'INTEGER');
    await _ensureBackupPlanColumn(db, 'schedule_once_at', 'TEXT');
  }

  Future<void> _upgradeToV4(Database db) async {
    await _ensureBackupPlanColumn(
      db,
      'schedule_status',
      "TEXT DEFAULT 'unscheduled'",
    );
    await _ensureBackupPlanColumn(db, 'schedule_error', 'TEXT');
    await _ensureBackupPlanColumn(db, 'scheduled_run_at', 'TEXT');
  }

  Future<void> _ensureBackupPlanColumn(
    Database db,
    String columnName,
    String sqlType,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(backup_plans)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE backup_plans ADD COLUMN $columnName $sqlType',
      );
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(
      table,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final db = await database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
  }

  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }
}
