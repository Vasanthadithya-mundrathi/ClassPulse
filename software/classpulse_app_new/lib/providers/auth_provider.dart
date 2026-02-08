import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/student_profile.dart';
import '../services/secure_storage_service.dart';
import '../services/network_service.dart';

enum AuthStatus { unknown, unregistered, registered }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  StudentProfile? _profile;
  final SecureStorageService _storage = SecureStorageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthStatus get status => _status;
  StudentProfile? get profile => _profile;

  AuthProvider() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _ensureFirebaseSession();
      
      final storedProfile = await _storage.readProfile();
      if (storedProfile == null) {
        _status = AuthStatus.unregistered;
      } else {
        _profile = storedProfile;
        _status = AuthStatus.registered;
      }
    } catch (e) {
      // Firebase not configured - check for stored profile
      debugPrint('Firebase session failed: $e');
      final storedProfile = await _storage.readProfile();
      if (storedProfile == null) {
        _status = AuthStatus.unregistered;
      } else {
        _profile = storedProfile;
        _status = AuthStatus.registered;
      }
    }
    notifyListeners();
  }

  Future<void> registerStudent(
    StudentProfile profile,
    Map<String, dynamic> config,
  ) async {
    try {
      await _ensureFirebaseSession();

      await _firestore.collection('students').doc(profile.uuid).set({
        'uuid': profile.uuid,
        'name': profile.name,
        'rollNumber': profile.rollNumber,
        'year': profile.year,
        'department': profile.department,
        'section': profile.section,
        'registeredAt': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase registration skipped: $e');
      // Continue without Firebase - will register locally
    }

    // Register with Pi server (with error handling)
    try {
      await _registerWithPi(config: config, profile: profile);
    } catch (e) {
      debugPrint('Pi registration failed: $e');
      // Continue - can still work in offline mode
    }

    // Save locally (always works)
    await _storage.persistProfile(profile);
    _profile = profile;
    _status = AuthStatus.registered;
    notifyListeners();
  }

  Future<void> resetForTesting() async {
    await _storage.clear();
    _profile = null;
    _status = AuthStatus.unregistered;
    notifyListeners();
  }

  /// Public helper to force-send a registration payload to the Pi server.
  /// Returns null on success, or an error string on failure so callers can show
  /// a user-friendly message.
  Future<String?> sendRegistrationToPi({
    required StudentProfile profile,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _registerWithPi(config: config, profile: profile);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

extension on AuthProvider {
  Future<void> _ensureFirebaseSession() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  Future<void> _registerWithPi({
    required Map<String, dynamic> config,
    required StudentProfile profile,
  }) async {
    // Always try to register with Pi if credentials are configured
    // The pi_enabled toggle only affects heartbeat, not registration
    
    final token = config['registration_api_token']?.toString() ?? '';
    if (token.isEmpty || token == 'change-me') {
      debugPrint('⚠️ Skipping Pi registration - no valid API token configured');
      return;
    }
    
    final host = config['pi_ip']?.toString() ?? '';
    if (host.isEmpty) {
      debugPrint('⚠️ Skipping Pi registration - no Pi IP configured');
      return;
    }

    final scheme = config['pi_scheme']?.toString().isNotEmpty == true
        ? config['pi_scheme'].toString()
        : 'http';
    final port = int.tryParse(config['pi_port']?.toString() ?? '5000') ?? 5000;

    final uri = Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: '/api/register',
    );

    // Get WiFi SSID
    String? wifiSsid;
    String? wifiCanonical;
    try {
      final networkService = NetworkService();
      wifiSsid = await networkService.getWifiName();
      wifiCanonical = NetworkService.canonicalizeSsid(wifiSsid);
      debugPrint('📡 Current WiFi: ${wifiSsid ?? "Not connected"} (canonical: ${wifiCanonical ?? "-"})');
    } catch (e) {
      debugPrint('⚠️ Could not get WiFi SSID: $e');
    }

    final payload = {
      'uuid': profile.uuid,
      'name': profile.name,
      'rollNumber': profile.rollNumber,
      'year': profile.year,
      'department': profile.department,
      'section': profile.section,
      'wifiSSID': wifiSsid,
      'wifiSSIDCanonical': wifiCanonical,
    };

    debugPrint('📤 Registering with Pi at $uri');
    debugPrint('📦 Payload: $payload');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Auth-Token': token,
        },
        body: jsonEncode(payload),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw StateError('Pi registration timeout - Pi may be unreachable');
        },
      );

      debugPrint('📥 Pi response: ${response.statusCode}');
      debugPrint('📥 Pi body: ${response.body}');

      if (response.statusCode == 201) {
        debugPrint('✅ Successfully registered with Pi!');
      } else if (response.statusCode >= 400) {
        debugPrint('❌ Pi registration failed: ${response.statusCode}');
        throw StateError(
          'Pi registration failed with ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Pi registration error: $e');
      rethrow;
    }
  }
}
