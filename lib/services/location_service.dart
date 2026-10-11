import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class HotelLocationData {
  final String address;
  final String city;
  final double latitude;
  final double longitude;

  const HotelLocationData({
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  /// Returns PostGIS standard WKT Point format: POINT(longitude latitude)
  String toWktPoint() => 'POINT($longitude $latitude)';

  Map<String, dynamic> toMap() => {
        'address': address,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'location': toWktPoint(),
      };

  @override
  String toString() => '$address, $city ($latitude, $longitude)';
}

class PlaceSuggestion {
  final String title;
  final String subtitle;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  PlaceSuggestion({
    required this.title,
    required this.subtitle,
    this.latitude,
    this.longitude,
    this.placeId,
  });
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Optional Google Maps API Key. If empty, falls back seamlessly to open geocoding.
  static String googleMapsApiKey = "";

  /// 1. Fetch current physical GPS location and reverse-geocode to address & city
  Future<HotelLocationData?> getCurrentLocationWithAddress() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permissions are denied.");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permissions are permanently denied.");
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      return await reverseGeocode(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("Error fetching current GPS location: $e");
      return null;
    }
  }

  /// 2. Reverse geocode coordinates to street address and city
  Future<HotelLocationData> reverseGeocode(double lat, double lng) async {
    String address = "Coordinates: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}";
    String city = "Lahore";

    // Try Google Maps Geocoding if API key is supplied
    if (googleMapsApiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleMapsApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
            final firstResult = data['results'][0];
            address = firstResult['formatted_address'] ?? address;

            // Extract locality/city
            final components = firstResult['address_components'] as List?;
            if (components != null) {
              for (var comp in components) {
                final types = (comp['types'] as List?)?.cast<String>() ?? [];
                if (types.contains('locality') || types.contains('administrative_area_level_2')) {
                  city = comp['long_name'] ?? city;
                  break;
                }
              }
            }
            return HotelLocationData(
              address: address,
              city: city,
              latitude: lat,
              longitude: lng,
            );
          }
        }
      } catch (e) {
        debugPrint("Google reverse geocode error: $e");
      }
    }

    // High-reliability Fallback: OpenStreetMap Nominatim
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'NegooHotelPartnerApp/1.0 (contact@negoo.app)'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        final addrObj = data['address'] as Map<String, dynamic>?;

        if (displayName != null) {
          address = displayName;
        }

        if (addrObj != null) {
          city = addrObj['city'] ??
              addrObj['town'] ??
              addrObj['suburb'] ??
              addrObj['county'] ??
              addrObj['state'] ??
              city;
        }
      }
    } catch (e) {
      debugPrint("OpenStreetMap reverse geocode error: $e");
    }

    return HotelLocationData(
      address: address,
      city: city,
      latitude: lat,
      longitude: lng,
    );
  }

  /// 3. Search addresses / places via Google Places or OSM Nominatim
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    if (query.trim().length < 2) return [];

    // Try Google Places Autocomplete if API key is provided
    if (googleMapsApiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}&types=establishment|geocode&key=$googleMapsApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK') {
            final predictions = data['predictions'] as List;
            return predictions.map((p) {
              final structured = p['structured_formatting'] ?? {};
              return PlaceSuggestion(
                title: structured['main_text'] ?? p['description'],
                subtitle: structured['secondary_text'] ?? '',
                placeId: p['place_id'],
              );
            }).toList();
          }
        }
      } catch (e) {
        debugPrint("Google places search error: $e");
      }
    }

    // Seamless Fallback / Universal Auto-fetch: Nominatim
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=6',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'NegooHotelPartnerApp/1.0 (contact@negoo.app)'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List list = json.decode(response.body);
        return list.map((item) {
          final String name = item['name'] ?? item['display_name'].toString().split(',').first;
          final String display = item['display_name'] ?? '';
          final double lat = double.tryParse(item['lat'].toString()) ?? 0.0;
          final double lon = double.tryParse(item['lon'].toString()) ?? 0.0;

          return PlaceSuggestion(
            title: name.isEmpty ? display : name,
            subtitle: display,
            latitude: lat,
            longitude: lon,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint("Universal places search error: $e");
    }

    return [];
  }

  /// 4. Resolve full place coordinates for a selected suggestion
  Future<HotelLocationData?> resolvePlaceCoordinates(PlaceSuggestion suggestion) async {
    if (suggestion.latitude != null && suggestion.longitude != null) {
      return await reverseGeocode(suggestion.latitude!, suggestion.longitude!);
    }

    if (suggestion.placeId != null && googleMapsApiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=${suggestion.placeId}&fields=formatted_address,geometry,address_components&key=$googleMapsApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK') {
            final result = data['result'];
            final loc = result['geometry']['location'];
            final double lat = (loc['lat'] as num).toDouble();
            final double lng = (loc['lng'] as num).toDouble();
            final String address = result['formatted_address'] ?? suggestion.subtitle;

            String city = "Lahore";
            final components = result['address_components'] as List?;
            if (components != null) {
              for (var comp in components) {
                final types = (comp['types'] as List?)?.cast<String>() ?? [];
                if (types.contains('locality') || types.contains('administrative_area_level_2')) {
                  city = comp['long_name'] ?? city;
                  break;
                }
              }
            }

            return HotelLocationData(
              address: address,
              city: city,
              latitude: lat,
              longitude: lng,
            );
          }
        }
      } catch (e) {
        debugPrint("Google place details error: $e");
      }
    }

    return null;
  }
}
