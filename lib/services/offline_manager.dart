import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Manager cho offline support
class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  Database? _database;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  final _onlineController = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _onlineController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Initialize offline manager
  Future<void> initialize() async {
    try {
      await _initDatabase();
      await _setupConnectivityListener();
      debugPrint('✅ OfflineManager initialized');
    } catch (e) {
      debugPrint('❌ OfflineManager initialization failed: $e');
    }
  }

  /// Initialize SQLite database
  Future<void> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'offline_cache.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Messages table
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversationId TEXT NOT NULL,
            content TEXT NOT NULL,
            type INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            idFrom TEXT NOT NULL,
            idTo TEXT NOT NULL,
            isRead INTEGER NOT NULL,
            isSynced INTEGER DEFAULT 0,
            data TEXT NOT NULL
          )
        ''');

        // Conversations table
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            lastMessage TEXT,
            lastMessageTime TEXT,
            lastMessageType INTEGER,
            isGroup INTEGER,
            isPinned INTEGER,
            isMuted INTEGER,
            participants TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');

        // Pending operations table
        await db.execute('''
          CREATE TABLE pending_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            collection TEXT NOT NULL,
            documentId TEXT,
            data TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            retryCount INTEGER DEFAULT 0
          )
        ''');

        // Indexes
        await db.execute('''
          CREATE INDEX idx_messages_conversation 
          ON messages(conversationId, timestamp DESC)
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_sync 
          ON messages(isSynced, timestamp)
        ''');

        debugPrint('✅ Database tables created');
      },
    );
  }

  /// Setup connectivity listener
  Future<void> _setupConnectivityListener() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
    _onlineController.add(_isOnline);

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (result) {
        final wasOnline = _isOnline;
        _isOnline = result != ConnectivityResult.none;

        debugPrint('📡 Connectivity changed: $_isOnline');
        _onlineController.add(_isOnline);

        // Sync when coming back online
        if (!wasOnline && _isOnline) {
          debugPrint('🔄 Coming back online, syncing...');
          syncPendingOperations();
        }
      },
    );
  }

  // ========================================
  // MESSAGE CACHING
  // ========================================

  /// Cache messages
  Future<void> cacheMessages(List<MessageChat> messages) async {
    if (_database == null) return;

    final batch = _database!.batch();

    for (final message in messages) {
      batch.insert(
        'messages',
        {
          'id': message.id,
          'conversationId': message.conversationId,
          'content': message.content,
          'type': message.type,
          'timestamp': message.timestamp,
          'idFrom': message.idFrom,
          'idTo': message.idTo,
          'isRead': message.isRead ? 1 : 0,
          'isSynced': 1,
          'data': jsonEncode(message.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint('✅ Cached ${messages.length} messages');
  }

  /// Get cached messages
  Future<List<MessageChat>> getCachedMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    if (_database == null) return [];

    try {
      final result = await _database!.query(
        'messages',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return result
          .map((json) =>
              MessageChat.fromJson(jsonDecode(json['data'] as String)))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting cached messages: $e');
      return [];
    }
  }

  /// Add pending message
  Future<void> addPendingMessage(MessageChat message) async {
    if (_database == null) return;

    await _database!.insert(
      'messages',
      {
        'id': message.id,
        'conversationId': message.conversationId,
        'content': message.content,
        'type': message.type,
        'timestamp': message.timestamp,
        'idFrom': message.idFrom,
        'idTo': message.idTo,
        'isRead': 0,
        'isSynced': 0, // Not synced yet
        'data': jsonEncode(message.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Add to pending operations
    await _database!.insert('pending_operations', {
      'type': 'message_send',
      'collection': 'messages',
      'documentId': message.id,
      'data': jsonEncode(message.toJson()),
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Added pending message: ${message.id}');
  }

  // ========================================
  // CONVERSATION CACHING
  // ========================================

  /// Cache conversations
  Future<void> cacheConversations(List<Conversation> conversations) async {
    if (_database == null) return;

    final batch = _database!.batch();

    for (final conv in conversations) {
      batch.insert(
        'conversations',
        {
          'id': conv.id,
          'lastMessage': conv.lastMessage,
          'lastMessageTime': conv.lastMessageTime,
          'lastMessageType': conv.lastMessageType,
          'isGroup': conv.isGroup ? 1 : 0,
          'isPinned': conv.isPinned ? 1 : 0,
          'isMuted': conv.isMuted ? 1 : 0,
          'participants': jsonEncode(conv.participants),
          'data': jsonEncode(conv.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint('✅ Cached ${conversations.length} conversations');
  }

  /// Get cached conversations
  Future<List<Conversation>> getCachedConversations() async {
    if (_database == null) return [];

    try {
      final result = await _database!.query(
        'conversations',
        orderBy: 'lastMessageTime DESC',
      );

      return result
          .map((json) =>
              Conversation.fromJson(jsonDecode(json['data'] as String)))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting cached conversations: $e');
      return [];
    }
  }

  // ========================================
  // SYNC OPERATIONS
  // ========================================

  /// Sync pending operations when online
  Future<void> syncPendingOperations() async {
    if (_database == null || !_isOnline) return;

    try {
      final pending = await _database!.query(
        'pending_operations',
        orderBy: 'timestamp ASC',
      );

      debugPrint('🔄 Syncing ${pending.length} pending operations');

      for (final op in pending) {
        try {
          final type = op['type'] as String;
          final data = jsonDecode(op['data'] as String);

          switch (type) {
            case 'message_send':
              await _syncPendingMessage(data);
              break;
            // Add other operation types as needed
          }

          // Delete operation after successful sync
          await _database!.delete(
            'pending_operations',
            where: 'id = ?',
            whereArgs: [op['id']],
          );

          debugPrint('✅ Synced operation: ${op['id']}');
        } catch (e) {
          debugPrint('❌ Failed to sync operation: $e');

          // Increment retry count
          final retryCount = (op['retryCount'] as int) + 1;

          if (retryCount > 3) {
            // Delete after 3 failed attempts
            await _database!.delete(
              'pending_operations',
              where: 'id = ?',
              whereArgs: [op['id']],
            );
            debugPrint('🗑️ Deleted failed operation after 3 retries');
          } else {
            await _database!.update(
              'pending_operations',
              {'retryCount': retryCount},
              where: 'id = ?',
              whereArgs: [op['id']],
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    }
  }

  /// Sync pending message to Firestore
  Future<void> _syncPendingMessage(Map<String, dynamic> data) async {
    // Implementation depends on your Firestore structure
    // This is a placeholder
    debugPrint('📤 Syncing message to Firestore: ${data['id']}');

    // Update message as synced
    await _database!.update(
      'messages',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  // ========================================
  // CLEANUP
  // ========================================

  /// Clear old cached data
  Future<void> clearOldCache({
    Duration maxAge = const Duration(days: 7),
  }) async {
    if (_database == null) return;

    final cutoffTime =
        DateTime.now().subtract(maxAge).millisecondsSinceEpoch.toString();

    try {
      // Delete old messages
      final deletedMessages = await _database!.delete(
        'messages',
        where: 'timestamp < ? AND isSynced = 1',
        whereArgs: [cutoffTime],
      );

      debugPrint('🗑️ Deleted $deletedMessages old cached messages');
    } catch (e) {
      debugPrint('❌ Error clearing old cache: $e');
    }
  }

  /// Get cache stats
  Future<Map<String, int>> getCacheStats() async {
    if (_database == null) return {};

    try {
      final messages = await _database!.query('messages');
      final conversations = await _database!.query('conversations');
      final pending = await _database!.query('pending_operations');
      final unsynced = await _database!.query(
        'messages',
        where: 'isSynced = 0',
      );

      return {
        'messages': messages.length,
        'conversations': conversations.length,
        'pending': pending.length,
        'unsynced': unsynced.length,
      };
    } catch (e) {
      debugPrint('❌ Error getting cache stats: $e');
      return {};
    }
  }

  /// Dispose
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _onlineController.close();
    await _database?.close();
    debugPrint('✅ OfflineManager disposed');
  }
}
