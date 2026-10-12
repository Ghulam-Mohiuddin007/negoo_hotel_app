import 'package:negoo_hotel_app/services/redis_cache_service.dart';

/// Legacy BookingCacheService wrapper delegating to high-speed RedisCacheService
class BookingCacheService {
  static final BookingCacheService _instance = BookingCacheService._internal();
  factory BookingCacheService() => _instance;
  BookingCacheService._internal();

  final RedisCacheService _redis = RedisCacheService();

  static String formatUniqueBookingId(String rawId) =>
      RedisCacheService.formatUniqueBookingId(rawId);

  void buildMemoryIndex(List<Map<String, dynamic>> bookings) =>
      _redis.buildMemoryIndex(bookings);

  List<Map<String, dynamic>> searchBookings(
    String query,
    List<Map<String, dynamic>> fallbackList,
  ) =>
      _redis.searchBookings(query, fallbackList);

  Future<void> cacheBookings(
    String hotelId,
    List<Map<String, dynamic>> bookings,
  ) =>
      _redis.cacheBookings(hotelId, bookings);

  Future<List<Map<String, dynamic>>> getCachedBookings(String hotelId) =>
      _redis.getCachedBookings(hotelId);

  Future<void> cacheArchivedRecord(
    String hotelId,
    Map<String, dynamic> record,
  ) =>
      _redis.cacheArchivedRecord(hotelId, record);

  Future<List<Map<String, dynamic>>> getCachedArchivedGuests(String hotelId) =>
      _redis.getCachedArchivedGuests(hotelId);
}
