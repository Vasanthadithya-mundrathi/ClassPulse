import 'package:geolocator/geolocator.dart' as geo;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getWifiName() async {
    final statuses = await <Permission>[ 
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();

    if (statuses.values.any((status) => status.isDenied || status.isPermanentlyDenied)) {
      return null;
    }

    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return null;
    }

    final ssid = await _networkInfo.getWifiName();
    return _sanitizeSsid(ssid);
  }

  static String? canonicalizeSsid(String? value) {
    final sanitized = _sanitizeSsid(value);
    if (sanitized == null) return null;
    return sanitized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String? _sanitizeSsid(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll('"', '').trim();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }
}
