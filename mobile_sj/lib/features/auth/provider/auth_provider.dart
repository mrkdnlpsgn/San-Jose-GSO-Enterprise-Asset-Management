import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/offline/offline_credentials.dart';
import '../../../core/offline/offline_store.dart';
import '../../settings/provider/settings_provider.dart';
import '../data/auth_service.dart';
import '../model/user_model.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

/// Set when the server ended the session; the login screen shows it once.
final sessionExpiredNoticeProvider = StateProvider<String?>((ref) => null);

const _kLastUserKey = 'auth.lastUser';

class AuthNotifier extends AsyncNotifier<UserModel?> {
  late AuthService _service;
  bool _confirming = false;
  /// Signed in offline (password checked on the phone): there is no server session yet.
  bool _offlineSession = false;

  @override
  Future<UserModel?> build() async {
    _service = ref.read(authServiceProvider);
    ApiClient.instance.onSessionExpired = _onSessionExpired;
    // Remember who is signed in, so opening the app with no connection doesn't sign them out.
    listenSelf((_, next) {
      if (next.isLoading || next.hasError) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final user = next.valueOrNull;
      // The offline copy and outbox in use are this account's.
      OfflineStore.instance.useAccount(user?.username);
      if (user == null) {
        prefs.remove(_kLastUserKey);
      } else {
        prefs.setString(_kLastUserKey, jsonEncode(user.toJson()));
      }
    });
    // On app start, check if a valid session cookie already exists
    try {
      return await _service.fetchCurrentUser();
    } on ApiException catch (e) {
      // No connection, or the server is asleep: the session can't be checked, not refused.
      // Keep the user signed in from what was saved and check again once the server answers.
      if (!e.serverAsleep) rethrow;
      final saved = await _savedUser();
      if (saved == null) rethrow;
      OfflineStore.instance.useAccount(saved.username);
      Future.microtask(_confirmSessionWhenReachable);
      return saved;
    }
  }

  Future<UserModel?> _savedUser() async {
    final raw = ref.read(sharedPreferencesProvider).getString(_kLastUserKey);
    if (raw == null || !await ApiClient.instance.hasSessionCookie()) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Signed in from the saved user: once the server answers, ask it again — a refused
  // session goes back to sign-in, an accepted one refreshes the saved details.
  Future<void> _confirmSessionWhenReachable() async {
    if (_confirming) return;
    _confirming = true;
    try {
      await future; // build has stored the saved user
      while (state.valueOrNull != null) {
        if (!await ApiClient.instance.waitForServer()) continue; // still offline — keep waiting
        if (state.valueOrNull == null) return; // signed out meanwhile
        try {
          final user = await _service.fetchCurrentUser();
          if (user == null) {
            _onSessionExpired();
          } else {
            state = AsyncData(user);
          }
          return;
        } on ApiException catch (e) {
          if (!e.serverAsleep) return; // a real error — leave the session to later requests
        }
      }
    } finally {
      _confirming = false;
    }
  }

  // Any request found the session gone: drop it and let the router send the user to sign-in.
  void _onSessionExpired() {
    if (state.valueOrNull == null) return; // already signed out — several requests can fail at once
    ApiClient.instance.clearCookies();
    ref.read(sessionExpiredNoticeProvider.notifier).state = _offlineSession
        ? "You're back online. Sign in again to upload the changes saved on this phone."
        : 'Your session has expired. Please sign in again.';
    _offlineSession = false;
    state = const AsyncData(null);
  }

  Future<void> login(String identifier, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.login(identifier, password));
    await _rememberForOffline(identifier, password);
  }

  Future<void> completeForceChangePassword(String identifier, String currentPassword, String newPassword) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _service.forceChangePassword(identifier, currentPassword, newPassword));
    await _rememberForOffline(identifier, newPassword);
  }

  /// [password] is the one entered before the code, kept so this phone can sign in offline later.
  Future<void> completeLoginOtp(String identifier, String otp, {bool rememberDevice = false, String? password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _service.verifyLoginOtp(identifier, otp, rememberDevice: rememberDevice));
    if (password != null) await _rememberForOffline(identifier, password);
  }

  // A complete online sign-in: this phone may sign the same account in offline for a while.
  Future<void> _rememberForOffline(String identifier, String password) async {
    final user = state.valueOrNull;
    if (user == null) return;
    _offlineSession = false;
    try {
      await OfflineCredentials.instance.remember(identifier: identifier, password: password, user: user.toJson());
    } catch (_) {
      // offline sign-in just won't be available — never fail the real sign-in over it
    }
  }

  /// Signs in with no connection, checking the password against the one saved at the last
  /// online sign-in on this phone (see [OfflineCredentials]). Changes made meanwhile upload
  /// after the next online sign-in.
  Future<void> loginOffline(String identifier, String password) async {
    state = const AsyncLoading();
    try {
      final user = UserModel.fromJson(await OfflineCredentials.instance.verify(identifier, password));
      OfflineStore.instance.useAccount(user.username);
      _offlineSession = true;
      state = AsyncData(user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  // Re-triggers login with the original credentials so the backend can email a
  // fresh OTP (subject to its own resend cooldown) — used by the "Resend code"
  // action on the 2FA screen. Doesn't touch state the way login() does, since
  // the caller is already past the login screen and shouldn't flash a loading
  // state or have a RequiresTwoFactor "error" reappear in authProvider.
  Future<void> resendLoginOtp(String identifier, String password) async {
    try {
      await _service.login(identifier, password);
    } on RequiresTwoFactor {
      // Expected — this call exists purely for its email side effect.
    }
  }

  // Clears a MustChangePasswordRequired (or any) error left in state after the
  // caller has already handled it, so it isn't mistaken for a real auth failure.
  void clearError() {
    if (state.hasError) state = const AsyncData(null);
  }

  Future<void> logout() async {
    _offlineSession = false;
    await _service.logout();
    state = const AsyncData(null);
  }

  Future<void> acknowledgePrivacy() async {
    final ackAt = await _service.acknowledgePrivacy();
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(privacyAcknowledgedAt: ackAt));
  }

  // After uploading or removing the profile picture on My Account.
  void setAvatarUrl(String? url) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(avatarUrl: () => url));
  }
}
