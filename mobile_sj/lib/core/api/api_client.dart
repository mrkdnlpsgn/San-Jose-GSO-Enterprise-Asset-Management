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

  /// The live deployment (Render, HTTPS) — the default, so a phone works anywhere.
  static const String liveAddress = 'https://sjgso.onrender.com';

  /// The local Docker backend as seen from the Android emulator (10.0.2.2 is the
  /// emulator's alias for this computer's localhost). On Windows/desktop builds it's localhost.
  static String get localAddress => !kIsWeb && Platform.isAndroid ? '10.0.2.2:8080' : 'localhost:8080';

  static const String defaultAddress = liveAddress;

  /// "https://host" / "http://host:port" are used as given; a bare "host:port" means
  /// plain http (the local Docker backend). Always without a trailing slash.
  static String originFor(String address) {
    final a = address.trim().replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'/api$'), '');
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(a) ? a : 'http://$a';
  }

  static String _urlFor(String address) => '${originFor(address)}/api';

  /// The saved address, or null if using [defaultAddress].
  String? get serverAddressOverride => _prefs.getString(kServerAddressPrefsKey);

  String get effectiveAddress => serverAddressOverride ?? defaultAddress;

  /// Render's free tier sleeps after ~15 idle minutes and takes up to ~3 minutes to start
  /// (a ping service keeps it awake, but a redeploy still restarts it). Resolves once the
  /// server answers its health check; gives up after [maxWait]. Calls [onWaiting] the first
  /// time a check fails, so the screen can say what's happening.
  Future<bool> waitForServer({void Function()? onWaiting, Duration maxWait = const Duration(minutes: 5)}) async {
    final deadline = DateTime.now().add(maxWait);
    final probe = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      validateStatus: (_) => true,
    ));
    var notified = false;
    while (true) {
      try {
        final res = await probe.get('${originFor(effectiveAddress)}/actuator/health');
        final code = res.statusCode ?? 0;
        if (code > 0 && code < 500) return true; // any real answer means it's up
      } catch (_) {
        // no answer yet — still starting
      }
      if (DateTime.now().isAfter(deadline)) return false;
      if (!notified) {
        notified = true;
        onWaiting?.call();
      }
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    dio = Dio(BaseOptions(
      baseUrl: _urlFor(effectiveAddress),
      // a little longer than a LAN needs — the live server is on the internet
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
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
