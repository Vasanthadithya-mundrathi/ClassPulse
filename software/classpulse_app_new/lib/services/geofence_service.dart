import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

class GeofenceServiceWrapper {
  bool _initialized = false;

  Future<double?> distanceToTarget(double latitude, double longitude) async {
    if (!await _ensurePermissions()) {
      return null;
    }

    final position = await geo.Geolocator.getCurrentPosition(
      desiredAccuracy: geo.LocationAccuracy.high,
    );

    return geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );
  }

  Future<void> ensureGeofence({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    if (_initialized) return;
    if (!await _ensurePermissions()) return;
    // Simplified: just ensure permissions for now
    _initialized = true;
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();

    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      await geo.Geolocator.openAppSettings();
    }

    return statuses.values.every((status) => status.isGranted);
  }
}
