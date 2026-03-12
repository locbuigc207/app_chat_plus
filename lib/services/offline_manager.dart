import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  Database? _database;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  final _onlineController = StreamController<bool>.broadcast();

  Stream<bool> get onlineStream => _onlineController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  // =========================================================
  // INITIALIZE
  // =========================================================

  Future<void> initialize() async {
    await _initDatabase();
    await _setupConnectivity();

    debugPrint("✅ OfflineManager initialized");
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, "offline_cache.db");

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE messages(
          id TEXT PRIMARY KEY,
          data TEXT,
          isSynced INTEGER
        )
        ''');

        await db.execute('''
        CREATE TABLE conversations(
          id TEXT PRIMARY KEY,
          data TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE pending_operations(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT,
          data TEXT,
          retryCount INTEGER
        )
        ''');

        debugPrint("✅ SQLite tables created");
      },
    );
  }

  Future<void> _setupConnectivity() async {
    final result = await _connectivity.checkConnectivity();

    _isOnline = !result.contains(ConnectivityResult.none);
    _onlineController.add(_isOnline);

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;

      _isOnline = !results.contains(ConnectivityResult.none);

      debugPrint("📡 Connectivity changed: $_isOnline");

      _onlineController.add(_isOnline);

      if (!wasOnline && _isOnline) {
        syncPendingOperations();
      }
    });
  }

  // =========================================================
  // MESSAGE CACHE
  // =========================================================

  String _generateMessageId(MessageChat message) {
    return "${message.idFrom}_${message.timestamp}";
  }

  Future<void> cacheMessages(List<MessageChat> messages) async {
    if (_database == null) return;

    final batch = _database!.batch();

    for (final msg in messages) {
      final id = _generateMessageId(msg);

      batch.insert(
        "messages",
        {"id": id, "data": jsonEncode(msg.toJson()), "isSynced": 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    debugPrint("💾 Cached ${messages.length} messages");
  }

  Future<List<MessageChat>> getCachedMessages() async {
    if (_database == null) return [];

    final result = await _database!.query("messages");

    return result.map((row) {
      final json = jsonDecode(row["data"] as String);

      return MessageChat(
        idFrom: json["idFrom"],
        idTo: json["idTo"],
        timestamp: json["timestamp"],
        content: json["content"],
        type: json["type"],
        isDeleted: json["isDeleted"] ?? false,
        editedAt: json["editedAt"],
        isPinned: json["isPinned"] ?? false,
        isRead: json["isRead"] ?? false,
        readAt: json["readAt"],
      );
    }).toList();
  }

  Future<void> addPendingMessage(MessageChat message) async {
    if (_database == null) return;

    final id = _generateMessageId(message);

    await _database!.insert(
      "messages",
      {"id": id, "data": jsonEncode(message.toJson()), "isSynced": 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _database!.insert("pending_operations", {
      "type": "send_message",
      "data": jsonEncode(message.toJson()),
      "retryCount": 0
    });

    debugPrint("📝 Pending message stored");
  }

  // =========================================================
  // CONVERSATION CACHE
  // =========================================================

  Future<void> cacheConversations(List<Conversation> conversations) async {
    if (_database == null) return;

    final batch = _database!.batch();

    for (final conv in conversations) {
      batch.insert(
        "conversations",
        {"id": conv.id, "data": jsonEncode(conv.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    debugPrint("💾 Cached ${conversations.length} conversations");
  }

  Future<List<Conversation>> getCachedConversations() async {
    if (_database == null) return [];

    final result = await _database!.query("conversations");

    return result.map((row) {
      final json = jsonDecode(row["data"] as String);

      return Conversation(
        id: row["id"] as String,
        isGroup: json["isGroup"],
        participants: List<String>.from(json["participants"]),
        lastMessage: json["lastMessage"],
        lastMessageTime: json["lastMessageTime"],
        lastMessageType: json["lastMessageType"],
        isPinned: json["isPinned"] ?? false,
        pinnedAt: json["pinnedAt"],
        isMuted: json["isMuted"] ?? false,
      );
    }).toList();
  }

  // =========================================================
  // SYNC
  // =========================================================

  Future<void> syncPendingOperations() async {
    if (_database == null || !_isOnline) return;

    final pending = await _database!.query("pending_operations");

    for (final op in pending) {
      try {
        final type = op["type"];

        if (type == "send_message") {
          await _syncMessage(op);
        }

        await _database!.delete(
          "pending_operations",
          where: "id=?",
          whereArgs: [op["id"]],
        );

        debugPrint("✅ Synced operation ${op["id"]}");
      } catch (e) {
        final retry = (op["retryCount"] as int) + 1;

        if (retry > 3) {
          await _database!.delete(
            "pending_operations",
            where: "id=?",
            whereArgs: [op["id"]],
          );

          debugPrint("🗑 Removed failed operation");
        } else {
          await _database!.update(
            "pending_operations",
            {"retryCount": retry},
            where: "id=?",
            whereArgs: [op["id"]],
          );
        }
      }
    }
  }

  Future<void> _syncMessage(Map op) async {
    final data = jsonDecode(op["data"]);

    debugPrint("📤 Sync message ${data["content"]}");

    // TODO: Firestore send here
  }

  // =========================================================
  // CACHE CLEANUP
  // =========================================================

  Future<void> clearCache() async {
    if (_database == null) return;

    await _database!.delete("messages");
    await _database!.delete("conversations");

    debugPrint("🗑 Cache cleared");
  }

  Future<Map<String, int>> getCacheStats() async {
    if (_database == null) return {};

    final msg = Sqflite.firstIntValue(
            await _database!.rawQuery("SELECT COUNT(*) FROM messages")) ??
        0;

    final conv = Sqflite.firstIntValue(
            await _database!.rawQuery("SELECT COUNT(*) FROM conversations")) ??
        0;

    final pending = Sqflite.firstIntValue(await _database!
            .rawQuery("SELECT COUNT(*) FROM pending_operations")) ??
        0;

    return {"messages": msg, "conversations": conv, "pending": pending};
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _onlineController.close();
    await _database?.close();

    debugPrint("✅ OfflineManager disposed");
  }
}
