import 'package:flutter_test/flutter_test.dart';
import 'package:negoo_hotel_app/services/location_service.dart';

void main() {
  group('HotelLocationData Tests', () {
    test('Correctly formats PostGIS WKT Point string', () {
      const loc = HotelLocationData(
        address: 'Pearl Continental, Mall Road',
        city: 'Lahore',
        latitude: 31.5580,
        longitude: 74.3315,
      );

      expect(loc.toWktPoint(), 'POINT(74.3315 31.558)');
      expect(loc.city, 'Lahore');
      expect(loc.address, 'Pearl Continental, Mall Road');
      expect(loc.latitude, 31.5580);
      expect(loc.longitude, 74.3315);
    });

    test('Converts correctly to map', () {
      const loc = HotelLocationData(
        address: 'F-7 Markaz',
        city: 'Islamabad',
        latitude: 33.7215,
        longitude: 73.0560,
      );

      final map = loc.toMap();
      expect(map['city'], 'Islamabad');
      expect(map['location'], 'POINT(73.056 33.7215)');
    });
  });
}
