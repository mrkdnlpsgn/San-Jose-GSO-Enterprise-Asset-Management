import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';

/// Overridden in main.dart with the instance loaded before runApp(), so
/// SettingsNotifier.build() can read persisted values synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

enum TextSizeOption {
  small('Small', 0.85),
  normal('Default', 1.0),
  large('Large', 1.15);

  const TextSizeOption(this.label, this.scaleFactor);
  final String label;
  final double scaleFactor;
}

class SettingsState {
  final ThemeMode themeMode;
  final TextSizeOption textSize;
  final String serverAddress; // effective host:port the app currently talks to

  const SettingsState({required this.themeMode, required this.textSize, required this.serverAddress});

  SettingsState copyWith({ThemeMode? themeMode, TextSizeOption? textSize, String? serverAddress}) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      textSize: textSize ?? this.textSize,
      serverAddress: serverAddress ?? this.serverAddress,
    );
  }
}

const _kThemeModeKey = 'settings.themeMode';
const _kTextSizeKey = 'settings.textSize';

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<SettingsState> {
  late SharedPreferences _prefs;

  @override
  SettingsState build() {
    _prefs = ref.read(sharedPreferencesProvider);

    final themeModeName = _prefs.getString(_kThemeModeKey);
    final themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == themeModeName,
      orElse: () => ThemeMode.system,
    );

    final textSizeName = _prefs.getString(_kTextSizeKey);
    final textSize = TextSizeOption.values.firstWhere(
      (t) => t.name == textSizeName,
      orElse: () => TextSizeOption.normal,
    );

    return SettingsState(
      themeMode: themeMode,
      textSize: textSize,
      serverAddress: ApiClient.instance.effectiveAddress,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setTextSize(TextSizeOption size) async {
    state = state.copyWith(textSize: size);
    await _prefs.setString(_kTextSizeKey, size.name);
  }

  // Pass null (or empty) to reset to ApiClient.defaultAddress.
  Future<void> setServerAddress(String? address) async {
    await ApiClient.instance.updateServerAddress(address);
    state = state.copyWith(serverAddress: ApiClient.instance.effectiveAddress);
  }
}
