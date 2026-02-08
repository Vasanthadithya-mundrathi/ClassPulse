import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class HeartbeatService {
  Timer? _timer;
  bool _sending = false;
  Map<String, dynamic>? _fullProfile;
  Uri? _piBaseUrl;
  Map<String, String>? _headers;

  void start({
    required Uri endpoint,
    required Map<String, dynamic> basePayload,
    required Duration interval,
    Map<String, String>? headers,
    Future<Map<String, dynamic>> Function()? metricsBuilder,
    void Function(bool success)? onResult,
    Map<String, dynamic>? fullProfile, // Full student profile for auto-registration
    Uri? piBaseUrl, // Base URL for registration endpoint
  }) {
    _timer?.cancel();
    _fullProfile = fullProfile;
    _piBaseUrl = piBaseUrl;
    _headers = headers;

    Future<void> invoke() async {
      final success = await _send(
        endpoint: endpoint,
        basePayload: basePayload,
        headers: headers,
        metricsBuilder: metricsBuilder,
      );
      if (onResult != null) {
        onResult(success);
      }
    }

    invoke();
    _timer = Timer.periodic(interval, (_) => invoke());
  }

  Future<bool> _send({
    required Uri endpoint,
    required Map<String, dynamic> basePayload,
    Map<String, String>? headers,
    Future<Map<String, dynamic>> Function()? metricsBuilder,
  }) async {
    if (_sending) return false;
    _sending = true;
    try {
      final payload = Map<String, dynamic>.from(basePayload);
      if (metricsBuilder != null) {
        final metrics = await metricsBuilder();
        if (metrics.isNotEmpty) {
          payload['metrics'] = metrics;
        }
      }

      if (_fullProfile != null) {
        payload['profile'] = _fullProfile;
        final wifiCanonical = _fullProfile!['wifiSSIDCanonical'];
        if (wifiCanonical != null) {
          payload['wifiSSIDCanonical'] = wifiCanonical;
        }
        final wifiSsid = _fullProfile!['wifiSSID'];
        if (wifiSsid != null) {
          payload['wifiSSID'] = wifiSsid;
        }
      }

      print('📡 Sending heartbeat to ${endpoint.toString()} with payload: $payload');

      final response = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          if (headers != null) ...headers,
        },
        body: jsonEncode(payload),
      );

      print('📬 Heartbeat response ${response.statusCode}: ${response.body}');

      // Handle 404: UUID not found on Pi, trigger auto-registration
      if (response.statusCode == 404) {
        final responseData = jsonDecode(response.body);
        if (responseData['should_register'] == true && _fullProfile != null && _piBaseUrl != null) {
          print('📝 UUID not found on Pi, auto-registering student...');
          final registered = await _registerOnPi();
          if (registered) {
            print('✅ Auto-registration successful, retrying heartbeat...');
            // Retry heartbeat after successful registration
            return await _send(
              endpoint: endpoint,
              basePayload: basePayload,
              headers: headers,
              metricsBuilder: metricsBuilder,
            );
          } else {
            print('❌ Auto-registration failed');
            return false;
          }
        }
        return false;
      }

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('❌ Heartbeat error: $e');
      return false;
    } finally {
      _sending = false;
    }
  }

  Future<bool> _registerOnPi() async {
    if (_fullProfile == null || _piBaseUrl == null) {
      return false;
    }

    try {
      final registerUrl = _piBaseUrl!.replace(path: '/api/register');
      
      final response = await http.post(
        registerUrl,
        headers: {
          'Content-Type': 'application/json',
          if (_headers != null) ..._headers!,
        },
        body: jsonEncode(_fullProfile),
      );

      if (response.statusCode == 201) {
        print('✅ Successfully registered on Pi');
        return true;
      } else {
        print('❌ Registration failed with status ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Registration error: $e');
      return false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }
}
