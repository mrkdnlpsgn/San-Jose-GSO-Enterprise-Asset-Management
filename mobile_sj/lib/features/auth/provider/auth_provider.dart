import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../data/auth_service.dart';
import '../model/user_model.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

/// Set when the server ended the session; the login screen shows "your session expired" once.
final sessionExpiredNoticeProvider = StateProvider<bool>((ref) => false);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  late AuthService _service;

  @override
  Future<UserModel?> build() async {
    _service = ref.read(authServiceProvider);
    ApiClient.instance.onSessionExpired = _onSessionExpired;
    // On app start, check if a valid session cookie already exists
    return _service.fetchCurrentUser();
  }

  // Any request found the session gone: drop it and let the router send the user to sign-in.
  void _onSessionExpired() {
    if (state.valueOrNull == null) return; // already signed out — several requests can fail at once
    ApiClient.instance.clearCookies();
    ref.read(sessionExpiredNoticeProvider.notifier).state = true;
    state = const AsyncData(null);
  }

  Future<void> login(String identifier, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.login(identifier, password));
  }

  Future<void> completeForceChangePassword(String identifier, String currentPassword, String newPassword) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _service.forceChangePassword(identifier, currentPassword, newPassword));
  }

  Future<void> completeLoginOtp(String identifier, String otp, {bool rememberDevice = false}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _service.verifyLoginOtp(identifier, otp, rememberDevice: rememberDevice));
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
