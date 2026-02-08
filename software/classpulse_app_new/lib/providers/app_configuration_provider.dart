import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/remote_config_service.dart';
import '../services/secure_storage_service.dart';

class AppConfigurationProvider extends ChangeNotifier {
  final RemoteConfigService _remoteConfig = RemoteConfigService();
  final SecureStorageService _storage = SecureStorageService();

  bool _loading = true;
  Map<String, dynamic> _effectiveConfig = const {};
  Completer<void>? _readyCompleter;

  bool get loading => _loading;
  Map<String, dynamic> get effectiveConfig => _effectiveConfig;

  AppConfigurationProvider() {
    _readyCompleter = Completer<void>();
    _load();
  }

  Future<void> ensureLoaded() async {
    if (_readyCompleter != null) {
      await _readyCompleter!.future;
    }
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    _loading = true;
    _readyCompleter = Completer<void>();
    notifyListeners();

    final remote = await _remoteConfig.loadDefaults();
    final overrides = await _storage.readConfigOverrides();

    _effectiveConfig = {...remote, ...overrides};
    _loading = false;
    _readyCompleter?.complete();
    notifyListeners();
  }

  Future<void> persistOverride(String key, dynamic value) async {
    await _storage.persistConfigOverride(key, value);
    await _load();
  }

  Future<void> clearOverrides() async {
    await _storage.clearConfigOverrides();
    await _load();
  }

  String getString(String key, {String fallback = ''}) {
    final value = _effectiveConfig[key];
    if (value == null) return fallback;
    return value.toString();
  }

  int getInt(String key, {int fallback = 0}) {
    return int.tryParse(getString(key)) ?? fallback;
  }

  double getDouble(String key, {double fallback = 0}) {
    return double.tryParse(getString(key)) ?? fallback;
  }

  bool getBool(String key, {bool fallback = false}) {
    final value = getString(key).toLowerCase();
    if (value == 'true') return true;
    if (value == 'false') return false;
    return fallback;
  }
}
