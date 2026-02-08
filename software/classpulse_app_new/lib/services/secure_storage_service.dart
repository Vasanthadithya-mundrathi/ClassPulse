import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/student_profile.dart';

class SecureStorageService {
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    sharedPreferencesName: 'classpulse_secure',
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _profileKey = 'classpulse_profile';
  static const String _configOverridesKey = 'classpulse_config_overrides';

  Future<void> persistProfile(StudentProfile profile) async {
    await _storage.write(
      key: _profileKey,
      value: jsonEncode(profile.toJson()),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<StudentProfile?> readProfile() async {
    final raw = await _storage.read(
      key: _profileKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    if (raw == null) return null;
    return StudentProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> readConfigOverrides() async {
    final raw = await _storage.read(
      key: _configOverridesKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  Future<void> persistConfigOverride(String key, dynamic value) async {
    final overrides = await readConfigOverrides();
    overrides[key] = value;
    await _storage.write(
      key: _configOverridesKey,
      value: jsonEncode(overrides),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<void> clearConfigOverrides() async {
    await _storage.delete(
      key: _configOverridesKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<void> clear() async {
    await _storage.delete(
      key: _profileKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    await _storage.delete(
      key: _configOverridesKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  // Simple key-value storage for settings
  Future<String?> readSetting(String key) async {
    return await _storage.read(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<void> writeSetting(String key, String value) async {
    await _storage.write(
      key: key,
      value: value,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<void> deleteSetting(String key) async {
    await _storage.delete(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }
}
