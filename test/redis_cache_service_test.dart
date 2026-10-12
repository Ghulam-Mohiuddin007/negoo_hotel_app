import 'package:flutter_test/flutter_test.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RedisCacheService Tests', () {
    final redis = RedisCacheService();

    setUp(() async {
      await redis.flushAll();
    });

    test('Redis Basic String SET, GET, DEL, EXISTS', () async {
      await redis.set('hotel:101:name', 'Serena Hotel');
      expect(redis.exists('hotel:101:name'), isTrue);
      expect(redis.get<String>('hotel:101:name'), 'Serena Hotel');

      await redis.del('hotel:101:name');
      expect(redis.exists('hotel:101:name'), isFalse);
      expect(redis.get<String>('hotel:101:name'), isNull);
    });

    test('Redis Hashes HSET, HGET, HGETALL, HDEL', () {
      redis.hset('metadata:rooms', 'room_abc', {'type': 'Deluxe', 'price': 5000});
      final fetched = redis.hget<Map<String, dynamic>>('metadata:rooms', 'room_abc');
      expect(fetched, isNotNull);
      expect(fetched!['type'], 'Deluxe');
      expect(fetched['price'], 5000);

      final all = redis.hgetall('metadata:rooms');
      expect(all.containsKey('room_abc'), isTrue);

      redis.hdel('metadata:rooms', 'room_abc');
      expect(redis.hget('metadata:rooms', 'room_abc'), isNull);
    });

    test('Redis Sets SADD, SMEMBERS, SISMEMBER, SREM', () {
      redis.sadd('active_bids', 'bid_1');
      redis.sadd('active_bids', 'bid_2');
      expect(redis.sismember('active_bids', 'bid_1'), isTrue);
      expect(redis.sismember('active_bids', 'bid_99'), isFalse);

      final members = redis.smembers('active_bids');
      expect(members.contains('bid_1'), isTrue);
      expect(members.contains('bid_2'), isTrue);

      redis.srem('active_bids', 'bid_1');
      expect(redis.sismember('active_bids', 'bid_1'), isFalse);
    });

    test('Redis Lists LPUSH, RPUSH, LRANGE, LLEN', () {
      redis.lpush('recent_guests', 'Guest A');
      redis.lpush('recent_guests', 'Guest B');
      expect(redis.llen('recent_guests'), 2);

      final list = redis.lrange('recent_guests', 0, 1);
      expect(list.first, 'Guest B');
      expect(list.last, 'Guest A');
    });

    test('Unique Booking ID Standardization', () {
      expect(
        RedisCacheService.formatUniqueBookingId('c4a1b2d3-e4f5-6789-0123-abcdef456789'),
        'NEG-BK-C4A1B2D3',
      );
      expect(RedisCacheService.formatUniqueBookingId(''), 'NEG-BK-0000');
    });

    test('Inverted Index Instant Search', () async {
      final sampleBookings = [
        {
          'id': 'abc-123-def',
          'full_name': 'Ali Khan',
          'phone': '03001234567',
          'cnic': '3520212345671',
          'status': 'confirmed',
        },
        {
          'id': 'xyz-999-uvw',
          'full_name': 'Hamza Ahmed',
          'phone': '03219876543',
          'cnic': '3520198765432',
          'status': 'pending',
        },
      ];

      redis.buildMemoryIndex(sampleBookings);

      // Search by name
      final resName = redis.searchBookings('Ali', sampleBookings);
      expect(resName.length, 1);
      expect(resName.first['full_name'], 'Ali Khan');

      // Search by phone
      final resPhone = redis.searchBookings('0321', sampleBookings);
      expect(resPhone.length, 1);
      expect(resPhone.first['full_name'], 'Hamza Ahmed');

      // Search by unique ID
      final uniqueId = RedisCacheService.formatUniqueBookingId('abc-123-def');
      final resId = redis.searchBookings(uniqueId, sampleBookings);
      expect(resId.length, 1);
      expect(resId.first['id'], 'abc-123-def');
    });
  });
}
