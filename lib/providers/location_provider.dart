// lib/providers/location_provider.dart - MODERN UPGRADE
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final String address;
  final String shortAddress;
  final String mapsUrl;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.shortAddress,
    required this.mapsUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'shortAddress': shortAddress,
      'mapsUrl': mapsUrl,
    };
  }

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: json['latitude'] ?? 0.0,
      longitude: json['longitude'] ?? 0.0,
      address: json['address'] ?? '',
      shortAddress: json['shortAddress'] ?? '',
      mapsUrl: json['mapsUrl'] ?? '',
    );
  }
}

class LocationProvider {
  /// Request location permission
  Future<bool> requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        await Geolocator.openLocationSettings();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission permanently denied');
        await Geolocator.openAppSettings();
        return false;
      }

      print('✅ Location permission granted');
      return true;
    } catch (e) {
      print('❌ Error requesting location permission: $e');
      return false;
    }
  }

  /// Get current location with full details (like Zalo/Messenger)
  Future<LocationData?> getCurrentLocationWithDetails() async {
    try {
      // Get position
      final position = await getCurrentLocation();
      if (position == null) return null;

      // Get address from coordinates (reverse geocoding)
      final address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      // Generate Maps URL
      final mapsUrl = generateMapsLink(position);

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address['full'] ?? 'Unknown location',
        shortAddress: address['short'] ?? 'Unknown',
        mapsUrl: mapsUrl,
      );
    } catch (e) {
      print('❌ Error getting location with details: $e');
      return null;
    }
  }

  /// Get current position
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      print('✅ Location obtained: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ Error getting location: $e');
      return null;
    }
  }

  /// Get address from coordinates (reverse geocoding)
  Future<Map<String, String>> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) {
        return {
          'full':
              'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}',
          'short': 'Unknown location',
        };
      }

      final place = placemarks.first;

      // Build full address (like Messenger/Zalo)
      List<String> addressParts = [];

      if (place.name != null && place.name!.isNotEmpty) {
        addressParts.add(place.name!);
      }
      if (place.street != null &&
          place.street!.isNotEmpty &&
          place.street != place.name) {
        addressParts.add(place.street!);
      }
      if (place.subLocality != null && place.subLocality!.isNotEmpty) {
        addressParts.add(place.subLocality!);
      }
      if (place.locality != null && place.locality!.isNotEmpty) {
        addressParts.add(place.locality!);
      }
      if (place.administrativeArea != null &&
          place.administrativeArea!.isNotEmpty) {
        addressParts.add(place.administrativeArea!);
      }
      if (place.country != null && place.country!.isNotEmpty) {
        addressParts.add(place.country!);
      }

      final fullAddress = addressParts.isNotEmpty
          ? addressParts.join(', ')
          : 'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}';

      // Build short address (for preview)
      List<String> shortParts = [];
      if (place.name != null && place.name!.isNotEmpty) {
        shortParts.add(place.name!);
      }
      if (place.locality != null && place.locality!.isNotEmpty) {
        shortParts.add(place.locality!);
      }

      final shortAddress = shortParts.isNotEmpty
          ? shortParts.join(', ')
          : place.country ?? 'Unknown location';

      return {
        'full': fullAddress,
        'short': shortAddress,
      };
    } catch (e) {
      print('❌ Error getting address: $e');
      return {
        'full':
            'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}',
        'short': 'Unknown location',
      };
    }
  }

  /// Generate Google Maps link
  String generateMapsLink(Position position) {
    return 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
  }

  /// Format location message (modern style like Zalo/Messenger)
  String formatLocationMessage(LocationData locationData) {
    return '''📍 Location
${locationData.address}

🗺️ View on map:
${locationData.mapsUrl}''';
  }

  /// Parse location from message
  /// Parse location from message
  LocationData? parseLocationFromMessage(String message) {
    try {
      // Extract Maps URL first (more reliable)
      final urlPattern = RegExp(
          r'https://www\.google\.com/maps/search/\?api=1&query=([-\d.]+),([-\d.]+)');
      final urlMatch = urlPattern.firstMatch(message);

      if (urlMatch == null) return null;

      final lat = double.tryParse(urlMatch.group(1)!);
      final lng = double.tryParse(urlMatch.group(2)!);

      if (lat == null || lng == null) return null;

      // Validate coordinates
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        return null;
      }

      // Extract address (text between 📍 Location and 🗺️)
      String address = 'Location';
      final addressPattern = RegExp(r'📍 Location\n(.*?)\n\n🗺️', dotAll: true);
      final addressMatch = addressPattern.firstMatch(message);

      if (addressMatch != null && addressMatch.group(1) != null) {
        address = addressMatch.group(1)!.trim();
      }

      return LocationData(
        latitude: lat,
        longitude: lng,
        address: address,
        shortAddress: address.split(',').first,
        mapsUrl: urlMatch.group(0)!,
      );
    } catch (e) {
      print('❌ Error parsing location: $e');
      return null;
    }
  }

  /// Generate Maps link from coordinates
  String generateMapsLinkFromCoords(double lat, double lng) {
    return 'https://www.google.com/maps?q=$lat,$lng';
  }

  /// Check if message contains location
  bool isLocationMessage(String message) {
    return message.contains('📍 Location') &&
        message.contains('🗺️ View on map:');
  }

  /// Calculate distance between two positions
  double calculateDistance(Position start, Position end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Format distance to human readable string
  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else if (meters < 10000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '${(meters / 1000).toStringAsFixed(0)} km';
    }
  }

  /// Get nearby places name (simplified)
  Future<String?> getNearbyPlaceName(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      return place.name ?? place.street ?? place.locality;
    } catch (e) {
      print('❌ Error getting nearby place: $e');
      return null;
    }
  }

  /// Stream location updates
  Stream<Position> getLocationStream({
    int distanceFilter = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }
}
