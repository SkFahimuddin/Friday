import 'package:geolocator/geolocator.dart';
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

  static Future<void> logCurrentLocation() async {
    final position = await getCurrentLocation();
    if (position == null) return;

    await FridayDatabase.saveLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  static void startTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    Geolocator.getPositionStream(locationSettings: settings).listen((position) {
      FridayDatabase.saveLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    });
  }

  static Future<String> getLocationSummary() async {
    final locations = await FridayDatabase.getRecentLocations();
    if (locations.isEmpty) return 'No location data yet.';

    final buffer = StringBuffer();
    buffer.writeln('Recent locations:');
    for (final loc in locations.take(5)) {
      final time = loc['timestamp'].toString().substring(0, 16);
      buffer.writeln('- $time: (${loc['latitude'].toStringAsFixed(4)}, ${loc['longitude'].toStringAsFixed(4)})');
    }
    return buffer.toString();
  }
}