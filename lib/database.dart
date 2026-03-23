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
      version: 2,
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
        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            content TEXT,
            timestamp TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT,
            message TEXT,
            timestamp TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS memories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT,
              content TEXT,
              timestamp TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS conversations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              role TEXT,
              message TEXT,
              timestamp TEXT
            )
          ''');
        }
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

  // Save a memory
  static Future<void> saveMemory({
    required String type,
    required String content,
  }) async {
    final db = await database;
    await db.insert('memories', {
      'type': type,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Get recent memories
  static Future<List<Map<String, dynamic>>> getRecentMemories() async {
    final db = await database;
    return await db.query(
      'memories',
      orderBy: 'timestamp DESC',
      limit: 20,
    );
  }

  // Save conversation message
  static Future<void> saveConversation({
    required String role,
    required String message,
  }) async {
    final db = await database;
    await db.insert('conversations', {
      'role': role,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Get recent conversation history
  static Future<List<Map<String, dynamic>>> getRecentConversations({int limit = 10}) async {
    final db = await database;
    return await db.query(
      'conversations',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // Build full memory context for Friday
  static Future<String> buildMemoryContext() async {
    final buffer = StringBuffer();
    final now = DateTime.now();

    // Recent locations
    final locations = await getRecentLocations();
    if (locations.isNotEmpty) {
      buffer.writeln('LOCATION HISTORY:');
      for (final loc in locations.take(5)) {
        final time = loc['timestamp'].toString().substring(0, 16).replaceAll('T', ' ');
        final address = loc['address']?.isNotEmpty == true
            ? loc['address']
            : '${loc['latitude']}, ${loc['longitude']}';
        buffer.writeln('- $time: $address');
      }
      buffer.writeln();
    }

    // Recent memories
    final memories = await getRecentMemories();
    if (memories.isNotEmpty) {
      buffer.writeln('PERSONAL NOTES:');
      for (final mem in memories.take(5)) {
        final time = mem['timestamp'].toString().substring(0, 16).replaceAll('T', ' ');
        buffer.writeln('- [${mem['type']}] $time: ${mem['content']}');
      }
      buffer.writeln();
    }

    // Recent conversations
    final convos = await getRecentConversations(limit: 6);
    if (convos.isNotEmpty) {
      buffer.writeln('RECENT CONVERSATION:');
      final reversed = convos.reversed.toList();
      for (final msg in reversed) {
        final role = msg['role'] == 'user' ? 'User' : 'Friday';
        buffer.writeln('$role: ${msg['message']}');
      }
      buffer.writeln();
    }

    buffer.writeln('Current time: ${now.toString().substring(0, 16)}');

    return buffer.toString();
  }
}