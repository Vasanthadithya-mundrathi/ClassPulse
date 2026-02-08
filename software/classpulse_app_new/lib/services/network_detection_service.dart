import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkDetectionService {
  /// Check if device is connected to the target WiFi network
  Future<Map<String, dynamic>> checkWifiConnection(String targetSSID) async {
    try {
      final info = NetworkInfo();
      final wifiName = await info.getWifiName();
      final wifiIP = await info.getWifiIP();
      
      // Remove quotes from SSID if present
      final cleanSSID = wifiName?.replaceAll('"', '') ?? '';
      
      return {
        'connected': cleanSSID == targetSSID || targetSSID.isEmpty,
        'current_ssid': cleanSSID,
        'ip_address': wifiIP,
        'match': cleanSSID == targetSSID,
      };
    } catch (e) {
      debugPrint('WiFi check error: $e');
      return {
        'connected': false,
        'current_ssid': null,
        'ip_address': null,
        'match': false,
        'error': e.toString(),
      };
    }
  }

  /// Get device's current WiFi SSID
  Future<String?> getCurrentWifiSSID() async {
    try {
      final info = NetworkInfo();
      final wifiName = await info.getWifiName();
      return wifiName?.replaceAll('"', '');
    } catch (e) {
      debugPrint('Get WiFi SSID error: $e');
      return null;
    }
  }

  /// Get device's current IP address
  Future<String?> getCurrentIPAddress() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      debugPrint('Get IP address error: $e');
      return null;
    }
  }

  /// Get Pi's network information and location
  Future<Map<String, dynamic>?> getPiInfo(String piServerUrl, String apiToken) async {
    try {
      final uri = Uri.parse('$piServerUrl/api/pi-info');
      final response = await http.get(
        uri,
        headers: {
          'X-Auth-Token': apiToken,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      
      return null;
    } catch (e) {
      debugPrint('Get Pi info error: $e');
      return null;
    }
  }

  /// Test connection to Pi server
  Future<bool> testPiConnection(String piServerUrl) async {
    try {
      final uri = Uri.parse('$piServerUrl/healthz');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Pi connection test error: $e');
      return false;
    }
  }
}
