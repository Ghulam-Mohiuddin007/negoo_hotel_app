import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookingCacheService {
  static final BookingCacheService _instance = BookingCacheService._internal();
  factory BookingCacheService() => _instance;
  BookingCacheService._internal();

  // In-memory cache memory stores
  final Map<String, List<Map<String, dynamic>>> _memoryBookingsCache = {};
  final Map<String, List<Map<String, dynamic>>> _memoryArchivedCache = {};

  // High-performance Inverted Index Maps for O(1) Lookups
  final Map<String, Map<String, dynamic>> _bookingByIdIndex = {};
  final Map<String, Set<String>> _tokenSearchIndex = {};

  /// Generates a standardized, human-readable unique booking ID
  static String formatUniqueBookingId(String rawId) {
    if (rawId.isEmpty) return 'NEG-BK-0000';
    final cleaned = rawId.replaceAll('-', '').toUpperCase();
    final slice = cleaned.length >= 8 ? cleaned.substring(0, 8) : cleaned.padRight(8, '0');
    return 'NEG-BK-$slice';
  }

  /// Builds ultra-fast memory index for instant search & O(1) key lookups
  void buildMemoryIndex(List<Map<String, dynamic>> bookings) {
    _bookingByIdIndex.clear();
    _tokenSearchIndex.clear();

    for (var b in bookings) {
      final rawId = b['id']?.toString() ?? '';
      final uniqueId = formatUniqueBookingId(rawId);
      final fullName = (b['full_name']?.toString() ?? '').toLowerCase();
      final phone = (b['phone']?.toString() ?? '').toLowerCase();
      final cnic = (b['cnic']?.toString() ?? '').toLowerCase();

      // Store in ID Index (both raw UUID and formatted ID)
      if (rawId.isNotEmpty) _bookingByIdIndex[rawId] = b;
      _bookingByIdIndex[uniqueId] = b;

      // Index tokens for instant search
      final tokens = {
        uniqueId.toLowerCase(),
        rawId.toLowerCase(),
        phone,
        cnic,
        ...fullName.split(' ').where((w) => w.length >= 2),
      };

      for (var token in tokens) {
        if (!_tokenSearchIndex.containsKey(token)) {
          _tokenSearchIndex[token] = <String>{};
        }
        _tokenSearchIndex[token]!.add(rawId);
      }
    }
  }

  /// Search using cached memory index (returns matching bookings instantly)
  List<Map<String, dynamic>> searchBookings(String query, List<Map<String, dynamic>> fallbackList) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return fallbackList;

    final Set<String> matchedIds = {};

    // 1. Direct O(1) unique ID match
    final direct = _bookingByIdIndex[cleanQuery.toUpperCase()];
    if (direct != null) {
      final rawId = direct['id']?.toString();
      if (rawId != null) matchedIds.add(rawId);
    }

    // 2. Token index search
    for (var entry in _tokenSearchIndex.entries) {
      if (entry.key.contains(cleanQuery)) {
        matchedIds.addAll(entry.value);
      }
    }

    if (matchedIds.isNotEmpty) {
      return fallbackList.where((b) => matchedIds.contains(b['id']?.toString())).toList();
    }

    // 3. Substring fallback match
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

  /// Save bookings into memory and disk cache
  Future<void> cacheBookings(String hotelId, List<Map<String, dynamic>> bookings) async {
    _memoryBookingsCache[hotelId] = bookings;
    buildMemoryIndex(bookings);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(bookings);
      await prefs.setString('cache_bookings_$hotelId', jsonStr);
    } catch (e) {
      debugPrint("Persistent cache write error: $e");
    }
  }

  /// Retrieve bookings from memory or persistent disk cache
  Future<List<Map<String, dynamic>>> getCachedBookings(String hotelId) async {
    // Return memory cache first if present
    if (_memoryBookingsCache.containsKey(hotelId) && _memoryBookingsCache[hotelId]!.isNotEmpty) {
      return _memoryBookingsCache[hotelId]!;
    }

    // Read from disk cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cache_bookings_$hotelId');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = json.decode(jsonStr);
        final list = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        _memoryBookingsCache[hotelId] = list;
        buildMemoryIndex(list);
        return list;
      }
    } catch (e) {
      debugPrint("Persistent cache read error: $e");
    }

    return [];
  }

  /// Cache archived check-out records locally and in memory
  Future<void> cacheArchivedRecord(String hotelId, Map<String, dynamic> record) async {
    if (!_memoryArchivedCache.containsKey(hotelId)) {
      _memoryArchivedCache[hotelId] = [];
    }
    _memoryArchivedCache[hotelId]!.insert(0, record);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(_memoryArchivedCache[hotelId]);
      await prefs.setString('cache_archived_$hotelId', jsonStr);
    } catch (e) {
      debugPrint("Archive cache error: $e");
    }
  }

  /// Get cached archived guests
  Future<List<Map<String, dynamic>>> getCachedArchivedGuests(String hotelId) async {
    if (_memoryArchivedCache.containsKey(hotelId)) {
      return _memoryArchivedCache[hotelId]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cache_archived_$hotelId');
      if (jsonStr != null) {
        final List decoded = json.decode(jsonStr);
        final list = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        _memoryArchivedCache[hotelId] = list;
        return list;
      }
    } catch (_) {}

    return [];
  }
}
