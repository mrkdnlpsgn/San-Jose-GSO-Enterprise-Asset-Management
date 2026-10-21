import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/provider/settings_provider.dart';

const _kOnboardingDoneKey = 'onboarding.done';

/// Whether this install has finished (or skipped) the first-launch onboarding.
final onboardingDoneProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_kOnboardingDoneKey) ?? false;

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_kOnboardingDoneKey, true);
  }
}
