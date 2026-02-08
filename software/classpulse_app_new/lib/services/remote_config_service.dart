import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  Future<Map<String, dynamic>> loadDefaults() async {
    // Default configuration (works offline without Firebase)
    final defaults = <String, dynamic>{
      'pi_scheme': 'http',
      'pi_ip': '10.124.80.185',
      'pi_port': '5000',
      'heartbeat_interval_seconds': '30',
      'min_rssi_threshold': '-70',
      'geofence_radius_meters': '50',
      'session_required_minutes': '45',
  'attendance_threshold_percent': '75',
      'target_wifi_ssid': 'ACE',
      'target_latitude': '17.4027',
      'target_longitude': '78.3398',
      'registration_api_token': 'HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM',
      'ble_beacon_uuid': 'aea91077-00fb-4345-b748-bd35c153c3a6',
      'camera_interval_minutes': '10',
      'sync_interval_minutes': '15',
    };

    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(minutes: 5),
        ),
      );

      await remoteConfig.setDefaults(defaults);
      await remoteConfig.fetchAndActivate();

      // Return Firebase values if available
      return remoteConfig.getAll().map(
        (key, value) => MapEntry(key, value.asString()),
      );
    } catch (e) {
      debugPrint('Firebase Remote Config failed, using defaults: $e');
      // Return hardcoded defaults if Firebase unavailable
      return defaults;
    }
  }
}
