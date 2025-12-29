import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gps_logs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      latitude REAL,
      longitude REAL,
      timestamp TEXT,
      source TEXT
    )
    ''');
  }

  // Insert a single log
  Future<int> insertLog(double lat, double lon, String source, {String? timestamp}) async {
    final db = await instance.database;
    final data = {
      'latitude': lat,
      'longitude': lon,
      'source': source,
      'timestamp': timestamp ?? DateTime.now().toIso8601String(),
    };
    return await db.insert('logs', data);
  }

  // Get all logs
  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await instance.database;
    return await db.query('logs', orderBy: 'timestamp DESC');
  }

  // Clear all data (optional, but useful for imports)
  Future<int> clearLogs() async {
    final db = await instance.database;
    return await db.delete('logs');
  }
}