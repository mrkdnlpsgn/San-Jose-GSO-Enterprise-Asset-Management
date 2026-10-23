import 'dart:io' show Platform;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/widgets/action_otp_dialog.dart' show ActionOtpOutcome;
import '../offline/offline_store.dart';
import '../offline/response_cache.dart';

const kServerAddressPrefsKey = 'settings.serverAddress';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio dio;
  late final PersistCookieJar _cookieJar;
  late final SharedPreferences _prefs;

  /// Answers GETs from the phone when the server can't be reached (see [ResponseCacheInterceptor]).
  final ResponseCacheInterceptor _cache = ResponseCacheInterceptor();

  /// True while the phone has no network at all - set from the connectivity provider.
  bool get deviceOffline => _cache.deviceOffline;
  set deviceOffline(bool value) => _cache.deviceOffline = value;

  /// The live deployment (Render, HTTPS) - the default, so a phone works anywhere.
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

  /// The saved address, or null if using [defaultAddress]. Debug builds only: the Connection
  /// screen is hidden in release builds, so an installed app always talks to the live server
  /// and can't be left pointing at a test address with no way to change it back.
  String? get serverAddressOverride => kDebugMode ? _prefs.getString(kServerAddressPrefsKey) : null;

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
        // no answer yet - still starting
      }
      if (DateTime.now().isAfter(deadline)) return false;
      // no network on the phone isn't the server starting up - don't say it is
      if (!notified && !deviceOffline) {
        notified = true;
        onWaiting?.call();
      }
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    await OfflineStore.instance.init();
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    dio = Dio(BaseOptions(
      baseUrl: _urlFor(effectiveAddress),
      // a little longer than a LAN needs - the live server is on the internet
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
    ));

    // Automatically stores the jwt HttpOnly cookie and sends it with every request
    dio.interceptors.add(CookieManager(_cookieJar));

    // Offline: answer GETs from the saved copy, fail everything else at once.
    dio.interceptors.add(_cache);

    // A status change or a decision on a staff request needs an emailed code: the server answers
    // 428 ACTION_OTP_REQUIRED (having emailed one), the prompt asks for it and repeats the request.
    dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) async {
      final data = e.response?.data;
      final prompt = actionOtpPrompt;
      if (e.response?.statusCode == 428 && data is Map && data['code'] == 'ACTION_OTP_REQUIRED'
          && e.requestOptions.extra['otpRetry'] != true && prompt != null) {
        final outcome = await prompt(
          data['message']?.toString() ?? 'Enter the 6-digit code we emailed you.',
          (code) => dio.fetch(_withActionOtp(e.requestOptions, code)),
        );
        if (outcome.response != null) return handler.resolve(outcome.response!);
        return handler.next(outcome.error ?? _cancelled(e.requestOptions));
      }
      handler.next(e);
    }));

    // Session over (the 1-hour token expired, password changed, account deactivated):
    // send the user back to sign-in instead of leaving every screen on an error.
    dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) async {
      if (await _isSessionGone(e)) onSessionExpired?.call();
      handler.next(e);
    }));
  }

  /// Called when a request shows the sign-in session has ended. Set by the auth provider.
  void Function()? onSessionExpired;

  /// Asks for the emailed confirmation code (see the 428 interceptor). Set in main.dart.
  Future<ActionOtpOutcome> Function(String message, Future<Response<dynamic>> Function(String? code) send)?
      actionOtpPrompt;

  static RequestOptions _withActionOtp(RequestOptions o, String? code) {
    final headers = Map<String, dynamic>.of(o.headers)..remove('X-Action-Otp');
    if (code != null) headers['X-Action-Otp'] = code;
    return o.copyWith(headers: headers, extra: {...o.extra, 'otpRetry': true});
  }

  // Cancel on the code prompt, shaped like any other API error so screens show it the usual way.
  static DioException _cancelled(RequestOptions o) => DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: o, statusCode: 499,
            data: {'message': 'Cancelled. Nothing was changed.'}),
      );

  Future<bool> _isSessionGone(DioException e) async {
    final status = e.response?.statusCode;
    final path = e.requestOptions.path;
    if (path.contains('/auth/')) return false; // sign-in screens handle their own errors
    if (status == 401) return true;
    // Older backends answer a missing sign-in with 403. The server deletes the jwt cookie
    // when it rejects an expired token, so a 403 with no jwt cookie left = signed out
    // (a real "no permission" 403 still has the cookie and is left to the screen).
    if (status == 403) {
      final cookies = await _cookieJar.loadForRequest(e.requestOptions.uri);
      return !cookies.any((c) => c.name == 'jwt');
    }
    return false;
  }

  // Applies immediately (no app restart needed) - pass null/empty to clear the
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

  /// Whether a sign-in cookie is still saved. The jar drops it once its 1-hour max-age
  /// passes, so this is false for a session the server would refuse anyway.
  Future<bool> hasSessionCookie() async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(dio.options.baseUrl));
    return cookies.any((c) => c.name == 'jwt');
  }
}
