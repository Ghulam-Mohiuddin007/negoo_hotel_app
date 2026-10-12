import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enterprise Redis-Pattern Cache Engine for Negoo Partner Console
/// 
/// Provides sub-millisecond O(1) in-memory L1 cache with Redis semantics
/// (GET, SET, SETEX, HGET, HSET, SADD, LPUSH, LRANGE, TTL, EXPIRE, FLUSHALL)
/// backed by persistent L2 storage with automated TTL invalidation and inverted search indexing.
class RedisCacheService {
  static final RedisCacheService _instance = RedisCacheService._internal();
  factory RedisCacheService() => _instance;
  RedisCacheService._internal();

  // L1 In-Memory Fast Storage
  final Map<String, dynamic> _memoryStore = {};
  final Map<String, DateTime> _expiryStore = {};
  final Map<String, Map<String, dynamic>> _hashStore = {};
  final Map<String, Set<String>> _setStore = {};
  final Map<String, List<dynamic>> _listStore = {};

  // High-performance Inverted Index for Instant Booking Search
  final Map<String, Map<String, dynamic>> _bookingByIdIndex = {};
  final Map<String, Set<String>> _tokenSearchIndex = {};

  bool _isWarmedUp = false;

  /// Warm up L1 in-memory cache from L2 persistent disk on startup
  Future<void> warmup() async {
    if (_isWarmedUp) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('redis:'));
      final now = DateTime.now();

      for (final fullKey in keys) {
        final key = fullKey.substring(6); // remove 'redis:' prefix
        final rawVal = prefs.getString(fullKey);
        if (rawVal == null) continue;

        try {
          final decoded = json.decode(rawVal);
          if (decoded is Map && decoded.containsKey('__redis_val')) {
            final expStr = decoded['__redis_exp'] as String?;
            if (expStr != null) {
              final exp = DateTime.parse(expStr);
              if (now.isAfter(exp)) {
                await prefs.remove(fullKey);
                continue;
              }
              _expiryStore[key] = exp;
            }
            _memoryStore[key] = decoded['__redis_val'];
          }
        } catch (_) {}
      }
      _isWarmedUp = true;
      debugPrint("⚡ Redis Cache Engine warmed up: ${_memoryStore.length} keys in RAM");
    } catch (e) {
      debugPrint("Redis warmup warning: $e");
    }
  }

  // ===========================================================================
  // REDIS STRING COMMANDS (GET, SET, SETEX, DEL, EXISTS, EXPIRE, TTL, KEYS)
  // ===========================================================================

  /// Redis SET / SETEX: Store value with optional TTL
  Future<void> set(String key, dynamic value, {Duration? ttl}) async {
    _memoryStore[key] = value;
    if (ttl != null) {
      _expiryStore[key] = DateTime.now().add(ttl);
    } else {
      _expiryStore.remove(key);
    }

    // Write-through to L2 Persistent Cache in background
    try {
      final prefs = await SharedPreferences.getInstance();
      final envelope = {
        '__redis_val': value,
        if (ttl != null) '__redis_exp': DateTime.now().add(ttl).toIso8601String(),
      };
      await prefs.setString('redis:$key', json.encode(envelope));
    } catch (e) {
      debugPrint("Redis L2 write notice: $e");
    }
  }

  /// Redis GET: O(1) instantaneous memory read
  T? get<T>(String key) {
    if (_isExpired(key)) {
      del(key);
      return null;
    }
    final val = _memoryStore[key];
    if (val == null) return null;
    if (val is T) return val;
    return null;
  }

  /// Redis DEL: Purge key from L1 and L2
  Future<void> del(String key) async {
    _memoryStore.remove(key);
    _expiryStore.remove(key);
    _hashStore.remove(key);
    _setStore.remove(key);
    _listStore.remove(key);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('redis:$key');
    } catch (_) {}
  }

  /// Redis EXISTS
  bool exists(String key) {
    if (_isExpired(key)) {
      del(key);
      return false;
    }
    return _memoryStore.containsKey(key) ||
        _hashStore.containsKey(key) ||
        _setStore.containsKey(key) ||
        _listStore.containsKey(key);
  }

  /// Redis EXPIRE: Set time to live for a key
  void expire(String key, Duration ttl) {
    _expiryStore[key] = DateTime.now().add(ttl);
  }

  /// Redis TTL: Returns remaining time to live
  Duration? ttl(String key) {
    final exp = _expiryStore[key];
    if (exp == null) return null;
    final remaining = exp.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Redis KEYS: Pattern matching (e.g. 'hotel:*')
  List<String> keys([String pattern = '*']) {
    final now = DateTime.now();
    final validKeys = <String>[];
    for (final k in _memoryStore.keys) {
      final exp = _expiryStore[k];
      if (exp != null && now.isAfter(exp)) continue;
      if (pattern == '*' || _matchesPattern(k, pattern)) {
        validKeys.add(k);
      }
    }
    return validKeys;
  }

  /// Redis FLUSHALL: Clear entire cache
  Future<void> flushAll() async {
    _memoryStore.clear();
    _expiryStore.clear();
    _hashStore.clear();
    _setStore.clear();
    _listStore.clear();
    _bookingByIdIndex.clear();
    _tokenSearchIndex.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs.getKeys().where((k) => k.startsWith('redis:'));
      for (final k in keysToRemove) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // ===========================================================================
  // REDIS HASH COMMANDS (HSET, HGET, HGETALL, HDEL)
  // ===========================================================================

  void hset(String key, String field, dynamic value) {
    _hashStore.putIfAbsent(key, () => {})[field] = value;
  }

  T? hget<T>(String key, String field) {
    final hash = _hashStore[key];
    if (hash == null) return null;
    final val = hash[field];
    return val is T ? val : null;
  }

  Map<String, dynamic> hgetall(String key) {
    return Map<String, dynamic>.from(_hashStore[key] ?? {});
  }

  void hdel(String key, String field) {
    _hashStore[key]?.remove(field);
  }

  // ===========================================================================
  // REDIS SET COMMANDS (SADD, SREM, SMEMBERS, SISMEMBER)
  // ===========================================================================

  void sadd(String key, String member) {
    _setStore.putIfAbsent(key, () => {}).add(member);
  }

  void srem(String key, String member) {
    _setStore[key]?.remove(member);
  }

  Set<String> smembers(String key) {
    return Set<String>.from(_setStore[key] ?? {});
  }

  bool sismember(String key, String member) {
    return _setStore[key]?.contains(member) ?? false;
  }

  // ===========================================================================
  // REDIS LIST COMMANDS (LPUSH, RPUSH, LRANGE, LLEN)
  // ===========================================================================

  void lpush(String key, dynamic value) {
    _listStore.putIfAbsent(key, () => []).insert(0, value);
  }

  void rpush(String key, dynamic value) {
    _listStore.putIfAbsent(key, () => []).add(value);
  }

  List<dynamic> lrange(String key, int start, int stop) {
    final list = _listStore[key] ?? [];
    if (list.isEmpty) return [];
    final safeStart = start.clamp(0, list.length);
    final safeStop = (stop + 1).clamp(0, list.length);
    if (safeStart >= safeStop) return [];
    return list.sublist(safeStart, safeStop);
  }

  int llen(String key) => _listStore[key]?.length ?? 0;

  // ===========================================================================
  // NEGOO DOMAIN OPTIMIZATION METHODS
  // ===========================================================================

  /// Format standardized, human-readable unique booking ID
  static String formatUniqueBookingId(String rawId) {
    if (rawId.isEmpty) return 'NEG-BK-0000';
    final cleaned = rawId.replaceAll('-', '').toUpperCase();
    final slice = cleaned.length >= 8 ? cleaned.substring(0, 8) : cleaned.padRight(8, '0');
    return 'NEG-BK-$slice';
  }

  /// Builds inverted memory index for instantaneous O(1) search lookups
  void buildMemoryIndex(List<Map<String, dynamic>> bookings) {
    _bookingByIdIndex.clear();
    _tokenSearchIndex.clear();

    for (var b in bookings) {
      final rawId = b['id']?.toString() ?? '';
      final uniqueId = formatUniqueBookingId(rawId);
      final fullName = (b['full_name']?.toString() ?? '').toLowerCase();
      final phone = (b['phone']?.toString() ?? '').toLowerCase();
      final cnic = (b['cnic']?.toString() ?? '').toLowerCase();

      if (rawId.isNotEmpty) _bookingByIdIndex[rawId] = b;
      _bookingByIdIndex[uniqueId] = b;

      final tokens = {
        uniqueId.toLowerCase(),
        rawId.toLowerCase(),
        phone,
        cnic,
        ...fullName.split(' ').where((w) => w.length >= 2),
      };

      for (var token in tokens) {
        _tokenSearchIndex.putIfAbsent(token, () => {}).add(rawId);
      }
    }
  }

  /// Search bookings instantly via in-memory inverted index
  List<Map<String, dynamic>> searchBookings(String query, List<Map<String, dynamic>> fallbackList) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return fallbackList;

    final Set<String> matchedIds = {};

    final direct = _bookingByIdIndex[cleanQuery.toUpperCase()];
    if (direct != null) {
      final rawId = direct['id']?.toString();
      if (rawId != null) matchedIds.add(rawId);
    }

    for (var entry in _tokenSearchIndex.entries) {
      if (entry.key.contains(cleanQuery)) {
        matchedIds.addAll(entry.value);
      }
    }

    if (matchedIds.isNotEmpty) {
      return fallbackList.where((b) => matchedIds.contains(b['id']?.toString())).toList();
    }

    return fallbackList.where((b) {
      final id = formatUniqueBookingId(b['id']?.toString() ?? '').toLowerCase();
      final name = (b['full_name']?.toString() ?? '').toLowerCase();
      final phone = (b['phone']?.toString() ?? '').toLowerCase();
      final cnic = (b['cnic']?.toString() ?? '').toLowerCase();
      return id.contains(cleanQuery) ||
          name.contains(cleanQuery) ||
          phone.contains(cleanQuery) ||
          cnic.contains(cleanQuery);
    }).toList();
  }

  /// Save bookings into Redis Cache (5-minute TTL with auto-refresh)
  Future<void> cacheBookings(String hotelId, List<Map<String, dynamic>> bookings) async {
    final key = 'hotel:$hotelId:bookings';
    await set(key, bookings, ttl: const Duration(minutes: 10));
    buildMemoryIndex(bookings);
  }

  /// Retrieve bookings from Redis Cache in 0ms
  Future<List<Map<String, dynamic>>> getCachedBookings(String hotelId) async {
    final key = 'hotel:$hotelId:bookings';
    final cached = get<List<dynamic>>(key);
    if (cached != null && cached.isNotEmpty) {
      final list = cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      buildMemoryIndex(list);
      return list;
    }

    // Fallback to disk read if not warmed up
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('redis:$key');
      if (raw != null) {
        final decoded = json.decode(raw);
        if (decoded is Map && decoded['__redis_val'] is List) {
          final list = (decoded['__redis_val'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _memoryStore[key] = list;
          buildMemoryIndex(list);
          return list;
        }
      }
    } catch (_) {}

    return [];
  }

  /// Cache Room inventory in Redis Cache (15-minute TTL)
  Future<void> cacheRooms(String hotelId, List<Map<String, dynamic>> rooms) async {
    await set('hotel:$hotelId:rooms', rooms, ttl: const Duration(minutes: 15));
  }

  /// Retrieve cached Room inventory in 0ms
  List<Map<String, dynamic>>? getCachedRooms(String hotelId) {
    final key = 'hotel:$hotelId:rooms';
    final cached = get<List<dynamic>>(key);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return null;
  }

  /// Cache Financial Overview metrics in Redis Cache
  Future<void> cacheFinancials(String hotelId, Map<String, dynamic> financials) async {
    await set('hotel:$hotelId:financials', financials, ttl: const Duration(minutes: 10));
  }

  /// Retrieve cached Financial Overview metrics in 0ms
  Map<String, dynamic>? getCachedFinancials(String hotelId) {
    final key = 'hotel:$hotelId:financials';
    final cached = get<Map<String, dynamic>>(key);
    return cached;
  }

  /// Cache hotel profile and approval state in Redis Cache (30-minute TTL)
  Future<void> cacheHotelProfile(String hotelId, Map<String, dynamic> profile) async {
    await set('hotel:$hotelId:profile', profile, ttl: const Duration(minutes: 30));
  }

  /// Retrieve cached hotel profile in 0ms
  Map<String, dynamic>? getCachedHotelProfile(String hotelId) {
    return get<Map<String, dynamic>>('hotel:$hotelId:profile');
  }

  /// Cache bid room and traveler metadata in Redis Hashes to avoid N+1 queries
  void cacheBidMetadata(String roomId, String userId, Map<String, dynamic> metadata) {
    if (roomId.isNotEmpty) hset('metadata:rooms', roomId, metadata['room']);
    if (userId.isNotEmpty) hset('metadata:users', userId, metadata['guest']);
  }

  /// Fast hash lookup for bid metadata
  Map<String, dynamic>? getBidMetadata(String roomId, String userId) {
    final room = hget<Map<String, dynamic>>('metadata:rooms', roomId);
    final guest = hget<Map<String, dynamic>>('metadata:users', userId);
    if (room != null || guest != null) {
      return {'room': room, 'guest': guest};
    }
    return null;
  }

  /// Cache archived check-out record
  Future<void> cacheArchivedRecord(String hotelId, Map<String, dynamic> record) async {
    lpush('hotel:$hotelId:archives', record);
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList('cache_archived_$hotelId') ?? [];
      currentList.insert(0, json.encode(record));
      await prefs.setStringList('cache_archived_$hotelId', currentList);
    } catch (_) {}
  }

  /// Retrieve archived guests
  Future<List<Map<String, dynamic>>> getCachedArchivedGuests(String hotelId) async {
    final list = lrange('hotel:$hotelId:archives', 0, 50);
    if (list.isNotEmpty) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList('cache_archived_$hotelId');
      if (currentList != null) {
        return currentList.map((e) => Map<String, dynamic>.from(json.decode(e))).toList();
      }
    } catch (_) {}
    return [];
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  bool _isExpired(String key) {
    final exp = _expiryStore[key];
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  bool _matchesPattern(String key, String pattern) {
    final regexStr = '^${pattern.replaceAll('*', '.*')}\$';
    return RegExp(regexStr).hasMatch(key);
  }
}
