import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class LocationData {
  final double latitude;
  final double longitude;
  final String address;
  final String shortAddress;
  final String mapsUrl;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.shortAddress,
    required this.mapsUrl,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'shortAddress': shortAddress,
    'mapsUrl': mapsUrl,
  };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    address: json['address'] as String? ?? '',
    shortAddress: json['shortAddress'] as String? ?? '',
    mapsUrl: json['mapsUrl'] as String? ?? '',
  );

  @override
  String toString() => 'LocationData($shortAddress, $latitude, $longitude)';
}

/// Result item from [LocationProvider.searchAddresses].
class LocationSearchResult {
  final String name;
  final String fullAddress;
  final double latitude;
  final double longitude;

  const LocationSearchResult({
    required this.name,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
  });

  String get mapsUrl => 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  @override
  String toString() => 'LocationSearchResult($name @ $latitude,$longitude)';
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class LocationProvider {
  static const _locationTimeout = Duration(seconds: 15);

  // ── Permission & basic getters ─────────────────────────────────────────────

  Future<bool> requestLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        return false;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error requesting location permission: $e');
      return false;
    }
  }

  Future<Position?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _locationTimeout,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error getting location: $e');
      return null;
    }
  }

  Future<LocationData?> getCurrentLocationWithDetails() async {
    try {
      final position = await getCurrentLocation();
      if (position == null) return null;

      final address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address['full'] ?? _coordString(position.latitude, position.longitude),
        shortAddress: address['short'] ?? 'Unknown',
        mapsUrl: _buildMapsUrl(position.latitude, position.longitude),
      );
    } catch (e) {
      debugPrint('❌ Error getting location with details: $e');
      return null;
    }
  }

  // ── Address search ─────────────────────────────────────────────────────────

  /// Search for locations matching [query].
  /// Returns up to [maxResults] results.
  Future<List<LocationSearchResult>> searchAddresses(
      String query, {
        int maxResults = 5,
      }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final locations = await locationFromAddress(trimmed);
      final results = <LocationSearchResult>[];

      for (final loc in locations.take(maxResults)) {
        try {
          final pms = await placemarkFromCoordinates(loc.latitude, loc.longitude);
          final p = pms.isNotEmpty ? pms.first : null;

          // Build display name
          final name = _buildDisplayName(p, trimmed);

          // Build full address
          final fullParts = <String>[
            if (p?.street?.isNotEmpty == true) p!.street!,
            if (p?.subLocality?.isNotEmpty == true) p!.subLocality!,
            if (p?.locality?.isNotEmpty == true) p!.locality!,
            if (p?.administrativeArea?.isNotEmpty == true) p!.administrativeArea!,
            if (p?.country?.isNotEmpty == true) p!.country!,
          ];

          results.add(LocationSearchResult(
            name: name,
            fullAddress: fullParts.join(', '),
            latitude: loc.latitude,
            longitude: loc.longitude,
          ));
        } catch (_) {}
      }
      return results;
    } catch (e) {
      debugPrint('❌ searchAddresses error: $e');
      return [];
    }
  }

  /// Reverse geocode [latitude],[longitude] into a [LocationSearchResult].
  Future<LocationSearchResult?> reverseGeocode(double latitude, double longitude) async {
    try {
      final pms = await placemarkFromCoordinates(latitude, longitude);
      if (pms.isEmpty) return null;

      final p = pms.first;
      final name = _buildDisplayName(p, '');

      final full = <String>[
        if (p.name?.isNotEmpty == true) p.name!,
        if (p.street?.isNotEmpty == true && p.street != p.name) p.street!,
        if (p.subLocality?.isNotEmpty == true) p.subLocality!,
        if (p.locality?.isNotEmpty == true) p.locality!,
        if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
        if (p.country?.isNotEmpty == true) p.country!,
      ];

      return LocationSearchResult(
        name: name,
        fullAddress: full.join(', '),
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('❌ reverseGeocode error: $e');
      return null;
    }
  }

  String _buildDisplayName(Placemark? p, String fallback) {
    if (p == null) return fallback.isNotEmpty ? fallback : 'Vị trí đã chọn';

    final parts = <String>[
      if (p.name?.isNotEmpty == true) p.name!,
      if (p.locality?.isNotEmpty == true) p.locality!,
    ];

    return parts.join(', ').isNotEmpty
        ? parts.join(', ')
        : fallback.isNotEmpty
        ? fallback
        : 'Vị trí đã chọn';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Map<String, String>> _getAddressFromCoordinates(
      double latitude,
      double longitude,
      ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isEmpty) {
        return {
          'full': _coordString(latitude, longitude),
          'short': 'Unknown location',
        };
      }

      final place = placemarks.first;
      final fullParts = <String>[];

      void addIfNotEmpty(String? s) {
        if (s != null && s.isNotEmpty) fullParts.add(s);
      }

      addIfNotEmpty(place.name);
      if (place.street != place.name) addIfNotEmpty(place.street);
      addIfNotEmpty(place.subLocality);
      addIfNotEmpty(place.locality);
      addIfNotEmpty(place.administrativeArea);
      addIfNotEmpty(place.country);

      final fullAddress = fullParts.isNotEmpty
          ? fullParts.join(', ')
          : _coordString(latitude, longitude);

      final shortParts = <String>[];
      addIfNotEmpty(place.name);
      addIfNotEmpty(place.locality);

      final shortAddress = shortParts.isNotEmpty
          ? shortParts.join(', ')
          : (place.country ?? 'Unknown location');

      return {'full': fullAddress, 'short': shortAddress};
    } catch (e) {
      debugPrint('❌ Error getting address: $e');
      return {
        'full': _coordString(latitude, longitude),
        'short': 'Unknown location',
      };
    }
  }

  String _coordString(double lat, double lng) =>
      'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';

  String _buildMapsUrl(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  String generateMapsLink(Position position) =>
      _buildMapsUrl(position.latitude, position.longitude);

  String generateMapsLinkFromCoords(double lat, double lng) =>
      'https://www.google.com/maps?q=$lat,$lng';

  String formatLocationMessage(LocationData data) =>
      '📍 Location\n${data.address}\n\n🗺️ View on map:\n${data.mapsUrl}';

  String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    if (meters < 10000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${(meters / 1000).toStringAsFixed(0)} km';
  }

  bool isLocationMessage(String message) =>
      message.contains('📍 Location') && message.contains('🗺️ View on map:');

  LocationData? parseLocationFromMessage(String message) {
    try {
      final urlPattern = RegExp(
        r'https://www\.google\.com/maps/search/\?api=1&query=([-\d.]+),([-\d.]+)',
      );
      final urlMatch = urlPattern.firstMatch(message);
      if (urlMatch == null) return null;

      final lat = double.tryParse(urlMatch.group(1)!);
      final lng = double.tryParse(urlMatch.group(2)!);

      if (lat == null || lng == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

      String address = 'Location';
      final addressPattern = RegExp(r'📍 Location\n(.*?)\n\n🗺️', dotAll: true);
      final addressMatch = addressPattern.firstMatch(message);

      if (addressMatch?.group(1) != null) {
        address = addressMatch!.group(1)!.trim();
      }

      return LocationData(
        latitude: lat,
        longitude: lng,
        address: address,
        shortAddress: address.split(',').first.trim(),
        mapsUrl: urlMatch.group(0)!,
      );
    } catch (e) {
      debugPrint('❌ Error parsing location: $e');
      return null;
    }
  }

  double calculateDistance(Position start, Position end) =>
      Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );

  double calculateDistanceFromCoords(
      double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<String?> getNearbyPlaceName(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;
      return p.name ?? p.street ?? p.locality;
    } catch (e) {
      debugPrint('❌ Error getting nearby place: $e');
      return null;
    }
  }

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