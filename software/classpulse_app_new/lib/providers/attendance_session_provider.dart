import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/student_profile.dart';
import '../services/bluetooth_scanner.dart';
import '../services/geofence_service.dart';
import '../services/heartbeat_service.dart';
import '../services/network_service.dart';
import '../services/secure_storage_service.dart';

class AttendanceSessionProvider extends ChangeNotifier {
  final HeartbeatService _heartbeatService = HeartbeatService();
  final BluetoothScanner _bluetoothScanner = BluetoothScanner();
  final NetworkService _networkService = NetworkService();
  final GeofenceServiceWrapper _geofenceService = GeofenceServiceWrapper();
  final SecureStorageService _storage = SecureStorageService();

  bool _active = false;
  bool _piEnabled = false;
  DateTime? _lastHeartbeatAt;
  int? _lastRssi;
  String? _currentSsid;
  bool _wifiMatch = false;
  bool? _insideGeofence;
  double? _geofenceDistanceMeters;
  Map<String, dynamic> _lastMetrics = const {};
  Timer? _pollTimer;

  bool get active => _active;
  bool get piEnabled => _piEnabled;
  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;
  int? get lastRssi => _lastRssi;
  String? get currentSsid => _currentSsid;
  bool get wifiMatch => _wifiMatch;
  bool? get insideGeofence => _insideGeofence;
  double? get geofenceDistanceMeters => _geofenceDistanceMeters;
  Map<String, dynamic> get lastMetrics => _lastMetrics;

  Future<void> startSession({
    required StudentProfile profile,
    required Map<String, dynamic> config,
  }) async {
    if (_active) return;
    _active = true;
    
    // Check if Pi connection is enabled
    final piEnabledStr = await _storage.readSetting('pi_enabled');
    _piEnabled = piEnabledStr == 'true';
    
    notifyListeners();

    final heartbeatIntervalSeconds = _parseInt(config['heartbeat_interval_seconds'], 30);
    final latitude = _parseDouble(config['target_latitude']);
    final longitude = _parseDouble(config['target_longitude']);
    final geofenceRadius = _parseDouble(config['geofence_radius_meters'], 50);
    
    // Setup geofence
    if (latitude != null && longitude != null && geofenceRadius != null) {
      await _geofenceService.ensureGeofence(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: geofenceRadius,
      );
    }

    // Only start heartbeat if Pi is enabled
    if (_piEnabled) {
      final scheme = _stringValue(config['pi_scheme'], fallback: 'http');
      final host = _stringValue(config['pi_ip'], fallback: '192.168.0.10');
      final port = _parseInt(config['pi_port'], 5000);
      final token = _stringValue(config['registration_api_token']);

      if (token.isNotEmpty && token != 'change-me') {
        final endpoint = Uri(
          scheme: scheme,
          host: host,
          port: port,
          path: '/api/heartbeat',
        );

        final piBaseUrl = Uri(
          scheme: scheme,
          host: host,
          port: port,
        );

        // Get WiFi SSID for registration
        final wifiSsid = await _networkService.getWifiName();
        final wifiCanonical = NetworkService.canonicalizeSsid(wifiSsid);

        // Prepare full profile for auto-registration
        final fullProfile = {
          'uuid': profile.uuid,
          'name': profile.name,
          'rollNumber': profile.rollNumber,
          'year': profile.year,
          'department': profile.department,
          'section': profile.section,
          'wifiSSID': wifiSsid,
          'wifiSSIDCanonical': wifiCanonical,
        };

        _heartbeatService.start(
          endpoint: endpoint,
          basePayload: {'uuid': profile.uuid},
          headers: {'X-Auth-Token': token},
          interval: Duration(seconds: heartbeatIntervalSeconds),
          fullProfile: fullProfile,
          piBaseUrl: piBaseUrl,
          metricsBuilder: () async {
            final metrics = await _collectMetrics(config);
            fullProfile['wifiSSID'] = metrics['wifi_ssid'];
            fullProfile['wifiSSIDCanonical'] = metrics['wifi_canonical'];
            _lastMetrics = metrics;
            notifyListeners();
            return metrics;
          },
          onResult: (success) {
            if (success) {
              _lastHeartbeatAt = DateTime.now();
              notifyListeners();
            }
          },
        );
      } else {
        debugPrint('Skipping Pi heartbeat - no valid API token');
      }
    } else {
      debugPrint('Pi connection disabled - working in offline mode');
    }

    // Always collect local metrics (even without Pi)
    final pollSeconds = heartbeatIntervalSeconds.clamp(10, 60);
    final pollPeriod = Duration(seconds: pollSeconds.toInt());
    _pollTimer = Timer.periodic(pollPeriod, (_) async {
      final metrics = await _collectMetrics(config);
      _lastMetrics = metrics;
      notifyListeners();
    });
  }

  Future<Map<String, dynamic>> _collectMetrics(Map<String, dynamic> config) async {
    final metrics = <String, dynamic>{};

    final beaconUuid = _stringValue(config['ble_beacon_uuid']);
    if (beaconUuid.isNotEmpty) {
      final rssi = await _bluetoothScanner.scanForBeacon(beaconUuid: beaconUuid);
      if (rssi != null) {
        _lastRssi = rssi;
        metrics['rssi'] = rssi;
      }
    }

    final ssid = await _networkService.getWifiName();
    _currentSsid = ssid;
    final expectedSsid = _stringValue(config['target_wifi_ssid']);
    final canonicalActual = NetworkService.canonicalizeSsid(ssid);
    final canonicalExpected = NetworkService.canonicalizeSsid(expectedSsid);
    _wifiMatch = _evaluateWifiMatch(canonicalActual, canonicalExpected);
    metrics['wifi_ssid'] = ssid;
    metrics['wifi_canonical'] = canonicalActual;
    if (expectedSsid.isNotEmpty) {
      metrics['wifi_expected'] = expectedSsid;
    }
    if (canonicalExpected != null && canonicalExpected.isNotEmpty) {
      metrics['wifi_expected_canonical'] = canonicalExpected;
    }
    metrics['wifi_match'] = _wifiMatch;

    debugPrint(
      "📶 WiFi check → actual: ${ssid ?? 'unknown'} ($canonicalActual) | "
      "expected: ${expectedSsid.isEmpty ? 'any' : expectedSsid} ($canonicalExpected) | match: $_wifiMatch",
    );

  final latitude = _parseDouble(config['target_latitude']);
  final longitude = _parseDouble(config['target_longitude']);
  final geofenceRadius = _parseDouble(config['geofence_radius_meters'], 50) ?? 50.0;
    if (latitude != null && longitude != null) {
      final distance = await _geofenceService.distanceToTarget(latitude, longitude);
      _geofenceDistanceMeters = distance;
      if (distance != null) {
        _insideGeofence = distance <= geofenceRadius;
        metrics['geofence_distance_m'] = distance;
        metrics['geofence_state'] = _insideGeofence == true ? 'INSIDE' : 'OUTSIDE';
      }
    }

    return metrics;
  }

  Future<void> stopSession() async {
    if (!_active) return;
    _heartbeatService.stop();
    _pollTimer?.cancel();
    _pollTimer = null;
    _active = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatService.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  int _parseInt(dynamic value, int fallback) {
    return int.tryParse(_stringValue(value)) ?? fallback;
  }

  double? _parseDouble(dynamic value, [double? fallback]) {
    final parsed = double.tryParse(_stringValue(value));
    return parsed ?? fallback;
  }

  bool _evaluateWifiMatch(String? actual, String? expected) {
    if (expected == null || expected.isEmpty) {
      return actual != null && actual.isNotEmpty;
    }
    if (actual == null || actual.isEmpty) {
      return false;
    }
    if (actual == expected) {
      return true;
    }
    return actual.contains(expected) || expected.contains(actual);
  }
}
