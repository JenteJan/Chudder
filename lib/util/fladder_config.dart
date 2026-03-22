import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class FladderConfig {
  static FladderConfig _instance = FladderConfig._();
  FladderConfig._();

  static String? get baseUrl => _instance._baseUrl;
  static set baseUrl(String? value) => _instance._baseUrl = value;
  String? _baseUrl;

  static String? get jellybotBaseUrl => _instance._jellybotBaseUrl;
  static set jellybotBaseUrl(String? value) => _instance._jellybotBaseUrl = value;
  String? _jellybotBaseUrl;

  static String? get seerrBaseUrl => _instance._seerrBaseUrl;
  static set seerrBaseUrl(String? value) => _instance._seerrBaseUrl = value;
  String? _seerrBaseUrl;

  static void fromJson(Map<String, dynamic> json) => _instance = FladderConfig._fromJson(json);

  /// Loads [config/config.json] from the asset bundle (all platforms).
  static Future<void> loadBundledConfig() async {
    try {
      final configString = await rootBundle.loadString('config/config.json');
      fromJson(jsonDecode(configString) as Map<String, dynamic>);
    } catch (e, stackTrace) {
      developer.log(
        'Failed to load config/config.json',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  factory FladderConfig._fromJson(Map<String, dynamic> json) {
    final config = FladderConfig._();
    final newUrl = json['baseUrl'] as String?;
    final newSeerrUrl = json['seerrBaseUrl'] as String?;

    config._baseUrl = newUrl?.isEmpty == true ? null : newUrl;
    config._seerrBaseUrl = newSeerrUrl?.isEmpty == true ? null : newSeerrUrl;
    final jellybotUrl = json['jellybotBaseUrl'] as String?;
    config._jellybotBaseUrl = jellybotUrl?.isEmpty == true ? null : jellybotUrl;
    return config;
  }
}
