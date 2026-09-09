import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_service.dart';
import '../model/user_model.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  late AuthService _service;

  @override
  Future<UserModel?> build() async {
    _service = ref.read(authServiceProvider);
    // On app start, check if a valid session cookie already exists
    return _service.fetchCurrentUser();
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

  Future<void> completeLoginOtp(String identifier, String otp) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.verifyLoginOtp(identifier, otp));
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
    state = AsyncData(UserModel(
      username: current.username,
      role: current.role,
      privacyAcknowledgedAt: ackAt,
    ));
  }
}
