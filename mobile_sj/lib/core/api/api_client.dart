import 'dart:io' show Platform;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kServerAddressPrefsKey = 'settings.serverAddress';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio dio;
  late final PersistCookieJar _cookieJar;
  late final SharedPreferences _prefs;

  // Android emulator → 10.0.2.2 (the emulator's alias for the host's localhost; a real
  // localhost inside the emulator's own virtual network resolves to the emulator itself).
  // Every other target (Windows/web/desktop, or a real device on the same Wi-Fi as the
  // backend) reaches the backend via the host machine directly.
  // Real device over Wi-Fi falls back to this only if no override is saved in
  // Settings — see serverAddress/updateServerAddress below.
  static const String defaultAddress = '192.168.1.7:8080';

  static String _urlFor(String address) => 'http://$address/api';

  /// The saved host:port, or null if using [defaultAddress].
  String? get serverAddressOverride => _prefs.getString(kServerAddressPrefsKey);

  String get effectiveAddress =>
      serverAddressOverride ?? (!kIsWeb && Platform.isAndroid ? defaultAddress : 'localhost:8080');

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    dio = Dio(BaseOptions(
      baseUrl: _urlFor(effectiveAddress),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ));

    // Automatically stores the jwt HttpOnly cookie and sends it with every request
    dio.interceptors.add(CookieManager(_cookieJar));
  }

  // Applies immediately (no app restart needed) — pass null/empty to clear the
  // override and fall back to defaultAddress.
  Future<void> updateServerAddress(String? address) async {
    final trimmed = address?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _prefs.remove(kServerAddressPrefsKey);
    } else {
      await _prefs.setString(kServerAddressPrefsKey, trimmed);
    }
    dio.options.baseUrl = _urlFor(effectiveAddress);
  }

  Future<void> clearCookies() async => _cookieJar.deleteAll();
}
