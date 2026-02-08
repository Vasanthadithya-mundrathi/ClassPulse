import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothScanner {
  Future<int?> scanForBeacon({
    required String beaconUuid,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) return null;

    int? bestRssi;
    final normalizedUuid = beaconUuid.replaceAll('-', '').toLowerCase();

    StreamSubscription<List<ScanResult>>? subscription;
    try {
      subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final advertisement = result.advertisementData;
          final manufacturerData = advertisement.manufacturerData.entries
              .expand((entry) => entry.value)
              .toList();
          final payload = _bytesToHex(manufacturerData);
          if (payload.contains(normalizedUuid)) {
            bestRssi = bestRssi == null
                ? result.rssi
                : (result.rssi > bestRssi! ? result.rssi : bestRssi);
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      return bestRssi;
    } finally {
      await subscription?.cancel();
    }
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
