import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class FridayDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'friday.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL,
            longitude REAL,
            address TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  // Save location
  static Future<void> saveLocation({
    required double latitude,
    required double longitude,
    String address = '',
  }) async {
    final db = await database;
    await db.insert('locations', {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Get last 20 locations
  static Future<List<Map<String, dynamic>>> getRecentLocations() async {
    final db = await database;
    return await db.query(
      'locations',
      orderBy: 'timestamp DESC',
      limit: 20,
    );
  }

  // Get locations for a specific date
  static Future<List<Map<String, dynamic>>> getLocationsByDate(String date) async {
    final db = await database;
    return await db.query(
      'locations',
      where: 'timestamp LIKE ?',
      whereArgs: ['$date%'],
      orderBy: 'timestamp ASC',
    );
  }
}