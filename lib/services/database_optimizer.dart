import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service để optimize database queries
class DatabaseOptimizer {
  static final DatabaseOptimizer _instance = DatabaseOptimizer._internal();
  factory DatabaseOptimizer() => _instance;
  DatabaseOptimizer._internal();

  // Cache cho frequently accessed data
  final Map<String, CachedData> _cache = {};
  static const _cacheDuration = Duration(minutes: 5);

  /// Get với caching
  Future<DocumentSnapshot?> getCached({
    required String collection,
    required String docId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$collection/$docId';

    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        debugPrint('📦 Cache hit: $cacheKey');
        return cached.data as DocumentSnapshot?;
      }
    }

    debugPrint('🔄 Cache miss, fetching: $cacheKey');
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .get();

      _cache[cacheKey] = CachedData(
        data: doc,
        timestamp: DateTime.now(),
      );

      return doc;
    } catch (e) {
      debugPrint('❌ Error fetching document: $e');
      return null;
    }
  }

  /// Batch get multiple documents
  Future<List<DocumentSnapshot>> batchGet({
    required String collection,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return [];

    // Check cache first
    final List<DocumentSnapshot> results = [];
    final List<String> toFetch = [];

    for (final docId in docIds) {
      final cacheKey = '$collection/$docId';
      if (_cache.containsKey(cacheKey)) {
        final cached = _cache[cacheKey]!;
        if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
          results.add(cached.data as DocumentSnapshot);
          continue;
        }
      }
      toFetch.add(docId);
    }

    if (toFetch.isEmpty) {
      debugPrint('📦 All from cache: ${docIds.length} documents');
      return results;
    }

    debugPrint('🔄 Fetching ${toFetch.length}/${docIds.length} documents');

    // Batch fetch remaining (max 10 per batch)
    const batchSize = 10;
    for (var i = 0; i < toFetch.length; i += batchSize) {
      final batch = toFetch.skip(i).take(batchSize).toList();

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final cacheKey = '$collection/${doc.id}';
          _cache[cacheKey] = CachedData(
            data: doc,
            timestamp: DateTime.now(),
          );
          results.add(doc);
        }
      } catch (e) {
        debugPrint('❌ Batch fetch error: $e');
      }
    }

    return results;
  }

  /// Query với pagination
  Future<PaginatedResult> queryPaginated({
    required String collection,
    required int limit,
    DocumentSnapshot? startAfter,
    List<QueryFilter>? filters,
    QueryOrder? orderBy,
  }) async {
    Query query = FirebaseFirestore.instance.collection(collection);

    // Apply filters
    if (filters != null) {
      for (final filter in filters) {
        query = query.where(
          filter.field,
          isEqualTo: filter.isEqualTo,
          isGreaterThan: filter.isGreaterThan,
          isLessThan: filter.isLessThan,
          arrayContains: filter.arrayContains,
        );
      }
    }

    // Apply ordering
    if (orderBy != null) {
      query = query.orderBy(
        orderBy.field,
        descending: orderBy.descending,
      );
    }

    // Apply pagination
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    query = query.limit(limit);

    try {
      final snapshot = await query.get();

      return PaginatedResult(
        documents: snapshot.docs,
        hasMore: snapshot.docs.length == limit,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('❌ Query error: $e');
      return PaginatedResult(
        documents: [],
        hasMore: false,
        lastDocument: null,
      );
    }
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
    debugPrint('🗑️ Cache cleared');
  }

  /// Clear specific cache entry
  void clearCacheEntry(String collection, String docId) {
    final cacheKey = '$collection/$docId';
    _cache.remove(cacheKey);
    debugPrint('🗑️ Cache entry removed: $cacheKey');
  }

  /// Get cache stats
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    int validEntries = 0;
    int expiredEntries = 0;

    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) < _cacheDuration) {
        validEntries++;
      } else {
        expiredEntries++;
      }
    }

    return {
      'total': _cache.length,
      'valid': validEntries,
      'expired': expiredEntries,
    };
  }
}

class CachedData {
  final dynamic data;
  final DateTime timestamp;

  CachedData({
    required this.data,
    required this.timestamp,
  });
}

class QueryFilter {
  final String field;
  final dynamic isEqualTo;
  final dynamic isGreaterThan;
  final dynamic isLessThan;
  final dynamic arrayContains;

  QueryFilter({
    required this.field,
    this.isEqualTo,
    this.isGreaterThan,
    this.isLessThan,
    this.arrayContains,
  });
}

class QueryOrder {
  final String field;
  final bool descending;

  QueryOrder({
    required this.field,
    this.descending = false,
  });
}

class PaginatedResult {
  final List<DocumentSnapshot> documents;
  final bool hasMore;
  final DocumentSnapshot? lastDocument;

  PaginatedResult({
    required this.documents,
    required this.hasMore,
    this.lastDocument,
  });
}
