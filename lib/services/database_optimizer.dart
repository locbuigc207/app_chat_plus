import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class CachedData<T> {
  final T data;
  final DateTime timestamp;
  final String key;

  const CachedData({
    required this.data,
    required this.timestamp,
    required this.key,
  });

  bool isExpired(Duration maxAge) => DateTime.now().difference(timestamp) >= maxAge;
}

class QueryFilter {
  final String field;
  final dynamic isEqualTo;
  final dynamic isNotEqualTo;
  final dynamic isGreaterThan;
  final dynamic isGreaterThanOrEqualTo;
  final dynamic isLessThan;
  final dynamic isLessThanOrEqualTo;
  final dynamic arrayContains;
  final List<dynamic>? arrayContainsAny;
  final List<dynamic>? whereIn;
  final bool? isNull;

  const QueryFilter({
    required this.field,
    this.isEqualTo,
    this.isNotEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.arrayContains,
    this.arrayContainsAny,
    this.whereIn,
    this.isNull,
  });
}

class QueryOrder {
  final String field;
  final bool descending;

  const QueryOrder({required this.field, this.descending = false});
}

class PaginatedResult {
  final List<DocumentSnapshot> documents;
  final bool hasMore;
  final DocumentSnapshot? lastDocument;
  final int totalFetched;

  const PaginatedResult({
    required this.documents,
    required this.hasMore,
    this.lastDocument,
    this.totalFetched = 0,
  });

  bool get isEmpty => documents.isEmpty;
}

class CacheStats {
  final int total;
  final int valid;
  final int expired;
  final int hitCount;
  final int missCount;

  const CacheStats({
    required this.total,
    required this.valid,
    required this.expired,
    required this.hitCount,
    required this.missCount,
  });

  double get hitRate => (hitCount + missCount) == 0 ? 0 : hitCount / (hitCount + missCount);

  Map<String, dynamic> toMap() => {
        'total': total,
        'valid': valid,
        'expired': expired,
        'hitCount': hitCount,
        'missCount': missCount,
        'hitRate': '${(hitRate * 100).toStringAsFixed(1)}%',
      };
}

class DatabaseOptimizer {
  static final DatabaseOptimizer _instance = DatabaseOptimizer._internal();
  factory DatabaseOptimizer() => _instance;
  DatabaseOptimizer._internal();

  final Map<String, CachedData<DocumentSnapshot>> _cache = {};

  final Map<String, Duration> _collectionTTL = {};
  static const Duration _defaultCacheDuration = Duration(minutes: 5);
  static const Duration _shortCacheDuration = Duration(minutes: 1);
  static const Duration _longCacheDuration = Duration(minutes: 15);

  int _hitCount = 0;
  int _missCount = 0;

  final Map<String, Timer> _debounceTimers = {};

  final Map<String, Map<String, dynamic>> _writeBehindQueue = {};
  Timer? _writeBehindFlushTimer;
  static const Duration _writeBehindDelay = Duration(seconds: 2);

  void setCollectionTTL(String collection, Duration ttl) {
    _collectionTTL[collection] = ttl;
  }

  Duration _getTTL(String collection) => _collectionTTL[collection] ?? _defaultCacheDuration;

  Future<DocumentSnapshot?> getCached({
    required String collection,
    required String docId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$collection/$docId';

    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired(_getTTL(collection))) {
        _hitCount++;
        debugPrint('📦 Cache hit: $cacheKey');
        return cached.data;
      }
    }

    _missCount++;
    debugPrint('🔄 Cache miss: $cacheKey');

    try {
      final doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();

      if (doc.exists) {
        _cache[cacheKey] = CachedData(
          data: doc,
          timestamp: DateTime.now(),
          key: cacheKey,
        );
      }

      return doc;
    } catch (e) {
      debugPrint('❌ Error fetching document $cacheKey: $e');

      return _cache[cacheKey]?.data;
    }
  }

  Future<List<DocumentSnapshot>> batchGet({
    required String collection,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return [];

    final results = <String, DocumentSnapshot>{};
    final toFetch = <String>[];
    final ttl = _getTTL(collection);

    for (final docId in docIds) {
      final cacheKey = '$collection/$docId';
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired(ttl)) {
        _hitCount++;
        results[docId] = cached.data;
      } else {
        _missCount++;
        toFetch.add(docId);
      }
    }

    if (toFetch.isEmpty) {
      debugPrint('📦 All ${docIds.length} docs from cache');
      return docIds.map((id) => results[id]!).whereType<DocumentSnapshot>().toList();
    }

    debugPrint('🔄 Fetching ${toFetch.length}/${docIds.length} docs');

    const chunkSize = 30;
    final fetchFutures = <Future<QuerySnapshot>>[];

    for (var i = 0; i < toFetch.length; i += chunkSize) {
      final chunk = toFetch.sublist(
        i,
        (i + chunkSize) > toFetch.length ? toFetch.length : i + chunkSize,
      );
      fetchFutures.add(
        FirebaseFirestore.instance
            .collection(collection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      );
    }

    final snapshots = await Future.wait(fetchFutures, eagerError: false);

    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final cacheKey = '$collection/${doc.id}';
        _cache[cacheKey] = CachedData(
          data: doc,
          timestamp: DateTime.now(),
          key: cacheKey,
        );
        results[doc.id] = doc;
      }
    }

    return docIds.map((id) => results[id]).whereType<DocumentSnapshot>().toList();
  }

  Future<PaginatedResult> queryPaginated({
    required String collection,
    required int limit,
    DocumentSnapshot? startAfter,
    List<QueryFilter>? filters,
    List<QueryOrder>? orderBy,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(collection);

      if (filters != null) {
        for (final f in filters) {
          if (f.isEqualTo != null) {
            query = query.where(f.field, isEqualTo: f.isEqualTo);
          }
          if (f.isNotEqualTo != null) {
            query = query.where(f.field, isNotEqualTo: f.isNotEqualTo);
          }
          if (f.isGreaterThan != null) {
            query = query.where(f.field, isGreaterThan: f.isGreaterThan);
          }
          if (f.isGreaterThanOrEqualTo != null) {
            query = query.where(f.field, isGreaterThanOrEqualTo: f.isGreaterThanOrEqualTo);
          }
          if (f.isLessThan != null) {
            query = query.where(f.field, isLessThan: f.isLessThan);
          }
          if (f.isLessThanOrEqualTo != null) {
            query = query.where(f.field, isLessThanOrEqualTo: f.isLessThanOrEqualTo);
          }
          if (f.arrayContains != null) {
            query = query.where(f.field, arrayContains: f.arrayContains);
          }
          if (f.arrayContainsAny != null) {
            query = query.where(f.field, arrayContainsAny: f.arrayContainsAny);
          }
          if (f.whereIn != null) {
            query = query.where(f.field, whereIn: f.whereIn);
          }
          if (f.isNull != null) {
            query = query.where(f.field, isNull: f.isNull);
          }
        }
      }

      if (orderBy != null) {
        for (final o in orderBy) {
          query = query.orderBy(o.field, descending: o.descending);
        }
      }

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      for (final doc in snapshot.docs) {
        final cacheKey = '$collection/${doc.id}';
        _cache[cacheKey] = CachedData(
          data: doc,
          timestamp: DateTime.now(),
          key: cacheKey,
        );
      }

      return PaginatedResult(
        documents: snapshot.docs,
        hasMore: snapshot.docs.length == limit,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        totalFetched: snapshot.docs.length,
      );
    } catch (e) {
      debugPrint('❌ Paginated query error ($collection): $e');
      return const PaginatedResult(
        documents: [],
        hasMore: false,
        lastDocument: null,
      );
    }
  }

  Future<void> updateOptimistic({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final cacheKey = '$collection/$docId';
    _clearCacheKey(cacheKey);

    _writeBehindQueue['$collection/$docId'] = {
      'collection': collection,
      'docId': docId,
      'data': data,
    };

    _writeBehindFlushTimer?.cancel();
    _writeBehindFlushTimer = Timer(_writeBehindDelay, _flushWriteBehind);

    debugPrint('⚡ Optimistic update queued: $cacheKey');
  }

  Future<void> _flushWriteBehind() async {
    if (_writeBehindQueue.isEmpty) return;

    final items = Map<String, Map<String, dynamic>>.from(_writeBehindQueue);
    _writeBehindQueue.clear();

    debugPrint('💾 Flushing ${items.length} write-behind operations');

    final futures = items.values.map((item) async {
      try {
        await FirebaseFirestore.instance
            .collection(item['collection'] as String)
            .doc(item['docId'] as String)
            .update(item['data'] as Map<String, dynamic>);
      } catch (e) {
        debugPrint('❌ Write-behind flush error: $e');

        _writeBehindQueue['${item['collection']}/${item['docId']}'] = item;
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  void debouncedWrite({
    required String key,
    required Duration delay,
    required Future<void> Function() write,
  }) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(delay, () async {
      _debounceTimers.remove(key);
      try {
        await write();
      } catch (e) {
        debugPrint('❌ Debounced write error ($key): $e');
      }
    });
  }

  void clearCache() {
    _cache.clear();
    debugPrint('🗑️ Cache fully cleared');
  }

  void clearCacheEntry(String collection, String docId) {
    _clearCacheKey('$collection/$docId');
  }

  void _clearCacheKey(String key) {
    _cache.remove(key);
    debugPrint('🗑️ Cache entry removed: $key');
  }

  void clearCollectionCache(String collection) {
    final keys = _cache.keys.where((k) => k.startsWith('$collection/')).toList();
    for (final k in keys) {
      _cache.remove(k);
    }
    debugPrint('🗑️ Collection cache cleared: $collection (${keys.length} entries)');
  }

  void evictExpired() {
    final keys = _cache.entries
        .where((e) => e.value.isExpired(_getTTL(
              e.key.split('/').first,
            )))
        .map((e) => e.key)
        .toList();
    for (final k in keys) {
      _cache.remove(k);
    }
    debugPrint('🗑️ Evicted ${keys.length} expired entries');
  }

  CacheStats getCacheStatsObject() {
    final now = DateTime.now();
    int valid = 0, expired = 0;

    for (final entry in _cache.entries) {
      final collection = entry.key.split('/').first;
      if (!entry.value.isExpired(_getTTL(collection))) {
        valid++;
      } else {
        expired++;
      }
    }

    return CacheStats(
      total: _cache.length,
      valid: valid,
      expired: expired,
      hitCount: _hitCount,
      missCount: _missCount,
    );
  }

  Map<String, dynamic> getCacheStats() => getCacheStatsObject().toMap();

  void resetStats() {
    _hitCount = 0;
    _missCount = 0;
  }

  void dispose() {
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    _writeBehindFlushTimer?.cancel();
    _flushWriteBehind();
    clearCache();
    debugPrint('✅ DatabaseOptimizer disposed');
  }
}
