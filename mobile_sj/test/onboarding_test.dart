import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/onboarding/provider/onboarding_provider.dart';
import 'package:san_jose_eam_mobile/features/onboarding/screens/onboarding_screen.dart';
import 'package:san_jose_eam_mobile/features/settings/provider/settings_provider.dart';

Future<ProviderContainer> pump(WidgetTester tester, {double scale = 1, bool reduceMotion = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  tester.view.physicalSize = const Size(360 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reduceMotion), child: child!),
      home: const OnboardingScreen(),
    ),
  ));
  return container;
}

void main() {
  testWidgets('pages through and marks onboarding done', (tester) async {
    final container = await pump(tester);
    expect(container.read(onboardingDoneProvider), isFalse);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    expect(find.text('AI-assisted insights'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await settle(tester);
    expect(container.read(onboardingDoneProvider), isTrue);
  });

  testWidgets('skip marks onboarding done', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(container.read(onboardingDoneProvider), isTrue);
  });

  testWidgets('no overflow on a small phone at large text', (tester) async {
    await pump(tester, scale: 1.6);
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await settle(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('with Reduce Motion the icons stay still once shown', (tester) async {
    await pump(tester, reduceMotion: true);
    await settle(tester);
    // nothing loops, so the screen settles
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a property tag'), findsOneWidget);
  });
}

// pumpAndSettle never returns while the icons loop, so step through frames instead
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
