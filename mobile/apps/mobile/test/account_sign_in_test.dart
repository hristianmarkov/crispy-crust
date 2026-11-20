import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crispy_crust/platform/cloud_session.dart';
import 'package:crispy_crust/platform/platform_result.dart';
import 'package:crispy_crust/screens/account_sign_in.dart';

class _PasswordCloud extends CloudSessionService {
  String? receivedEmail;
  String? receivedPassword;

  @override
  Future<CapabilityResult<bool>> connect(
    CloudConfiguration configuration,
  ) async => const CapabilityResult.available(true);

  @override
  Future<void> signInWithPassword(String email, String password) async {
    receivedEmail = email;
    receivedPassword = password;
  }
}

void main() {
  testWidgets(
    'password sign-in validates input and clears the password after submission',
    (tester) async {
      final cloud = _PasswordCloud();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountSignIn(
                cloud: cloud,
                onSignedIn: () {},
                configuration: const CloudConfiguration(
                  url: 'https://example.supabase.co',
                  publishableKey: 'test-public-key',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign in with email'));
      await tester.pump();
      await tester.tap(find.text('Use a password instead'));
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email address'),
        'review@example.com',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'fixture-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(cloud.receivedEmail, 'review@example.com');
      expect(cloud.receivedPassword, 'fixture-password');
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(field.controller!.text, isEmpty);
      expect(field.obscureText, isTrue);
      await tester.tap(find.text('Use an email code instead'));
      await tester.pump();
      expect(find.text('Send sign-in code'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    },
  );
}
