import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/shared/widgets/password_eye_button.dart';

void main() {
  testWidgets('eye button toggles the password and says what it will do', (tester) async {
    var obscured = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TextField(
            obscureText: obscured,
            decoration: InputDecoration(
              suffixIcon: PasswordEyeButton(obscured: obscured, onPressed: () => setState(() => obscured = !obscured)),
            ),
          ),
        ),
      ),
    ));

    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byType(PasswordEyeButton));
    await tester.pumpAndSettle();
    expect(obscured, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byType(PasswordEyeButton));
    await tester.pumpAndSettle();
    expect(obscured, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });
}
