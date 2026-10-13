import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _memory = <String, String>{};
  bool available = true;

  Future<String?> read(String key) async {
    if (!available) return _memory[key];
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      available = false;
      return _memory[key];
    }
  }

  Future<void> write(String key, String value) async {
    _memory[key] = value;
    if (!available) return;
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      available = false;
    }
  }

  Future<void> delete(String key) async {
    _memory.remove(key);
    if (!available) return;
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      available = false;
    }
  }

  Future<Map<String, String>> readMap(String key) async {
    final raw = await read(key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } on FormatException {
      return {};
    }
  }

  Future<void> writeMap(String key, Map<String, String> value) =>
      write(key, jsonEncode(value));
}

class MemorySecretStore extends SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
