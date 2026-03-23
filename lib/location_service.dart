import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'database.dart';

class LocationService {
  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  static Future<Position?> getCurrentLocation() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static Future<String> getAddressFromCoords(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = [
          place.street,
          place.subLocality,
          place.locality,
        ].where((p) => p != null && p.isNotEmpty).toList();
        return parts.join(', ');
      }
    } catch (e) {
      return '$lat, $lng';
    }
    return '$lat, $lng';
  }

  static Future<void> logCurrentLocation() async {
    final position = await getCurrentLocation();
    if (position == null) return;

    final address = await getAddressFromCoords(
      position.latitude,
      position.longitude,
    );

    await FridayDatabase.saveLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
  }

  static void startTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
      final address = await getAddressFromCoords(
        position.latitude,
        position.longitude,
      );
      FridayDatabase.saveLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );
    });
  }

  static Future<String> getLocationSummary() async {
    final locations = await FridayDatabase.getRecentLocations();
    if (locations.isEmpty) return 'No location data yet.';

    final buffer = StringBuffer();
    buffer.writeln('Recent locations:');
    for (final loc in locations.take(5)) {
      final time = loc['timestamp'].toString().substring(0, 16).replaceAll('T', ' ');
      final address = loc['address'] ?? '${loc['latitude']}, ${loc['longitude']}';
      buffer.writeln('- $time: $address');
    }
    return buffer.toString();
  }
}