import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/cloud_session.dart';

class AccountSignIn extends StatefulWidget {
  const AccountSignIn({
    super.key,
    required this.cloud,
    required this.onSignedIn,
    this.configuration = const CloudConfiguration.fromEnvironment(),
  });

  final CloudSessionService cloud;
  final VoidCallback onSignedIn;
  final CloudConfiguration configuration;

  @override
  State<AccountSignIn> createState() => _AccountSignInState();
}

class _AccountSignInState extends State<AccountSignIn> {
  final email = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  StreamSubscription<AuthState>? subscription;
  bool busy = false;
  bool emailOpen = false;
  bool passwordMode = false;
  bool reported = false;
  String? sentTo;
  String? message;

  CloudSessionService get cloud => widget.cloud;

  void reportSignIn() {
    if (!mounted || reported || !cloud.signedIn) return;
    reported = true;
    widget.onSignedIn();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final connection = await cloud.connect(widget.configuration);
      if (!mounted) return;
      if (!connection.isAvailable) {
        setState(() => message = connection.message);
        return;
      }
      subscription ??= cloud.authChanges?.listen((_) {
        if (!busy) reportSignIn();
      });
      if (!cloud.signedIn) await action();
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Sign-in could not finish. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reportSignIn();
      }
    }
  }

  Future<void> sendCode() async {
    final address = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(() => message = 'Enter a valid email address.');
      return;
    }
    await run(() async {
      await cloud.sendEmailCode(address);
      if (mounted) {
        setState(() {
          if (sentTo != address) code.clear();
          sentTo = address;
          message = 'Check your email for a sign-in code.';
        });
      }
    });
  }

  Future<void> signInWithPassword() async {
    final address = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(() => message = 'Enter a valid email address.');
      return;
    }
    if (password.text.isEmpty) {
      setState(() => message = 'Enter your password.');
      return;
    }
    await run(() async {
      try {
        await cloud.signInWithPassword(address, password.text);
      } finally {
        password.clear();
      }
    });
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    email.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.configuration.isConfigured;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cloud.supportsGoogleSignIn &&
            cloud.googleSignInConfigured &&
            configured)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    final ok = await cloud.signInWithGoogle();
                    if (!ok && mounted) {
                      setState(() => message = 'Google sign-in cancelled.');
                    }
                  }),
            style: OutlinedButton.styleFrom(
              side: BorderSide.none,
              padding: EdgeInsets.zero,
            ),
            child: Semantics(
              label: 'Sign in with Google',
              child: Opacity(
                opacity: busy ? 0.5 : 1,
                child: Image.asset(
                  dark
                      ? 'assets/brand/google-sign-in-dark.png'
                      : 'assets/brand/google-sign-in-light.png',
                  width: 180,
                  height: 40,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        if (configured &&
            (cloud.supportsAppleSignIn || cloud.appleBrowserSignInConfigured))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: SizedBox(
                width: 190,
                child: ExcludeSemantics(
                  excluding: busy,
                  child: IgnorePointer(
                    ignoring: busy,
                    child: SignInWithAppleButton(
                      height: 48,
                      style: dark
                          ? SignInWithAppleButtonStyle.white
                          : SignInWithAppleButtonStyle.black,
                      onPressed: () => run(() async {
                        if (cloud.supportsAppleBrowserSignIn) {
                          await cloud.signInWithAppleInBrowser();
                          if (mounted) {
                            setState(
                              () => message =
                                  'Continue in the Apple sign-in window.',
                            );
                          }
                        } else {
                          final ok = await cloud.signInWithApple();
                          if (!ok && mounted) {
                            setState(
                              () => message = 'Apple sign-in cancelled.',
                            );
                          }
                        }
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (configured)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    emailOpen = !emailOpen;
                    if (!emailOpen) password.clear();
                  }),
            child: Text(
              emailOpen ? 'Hide email sign-in' : 'Sign in with email',
            ),
          )
        else
          const Text('Account sign-in is unavailable in this build.'),
        if (emailOpen)
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email address'),
                  onChanged: (_) {
                    password.clear();
                    if (sentTo != null) {
                      code.clear();
                      setState(() => sentTo = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (passwordMode) ...[
                  TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) =>
                        busy ? null : unawaited(signInWithPassword()),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : signInWithPassword,
                    child: const Text('Sign in'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: busy ? null : sendCode,
                    child: Text(
                      sentTo == null ? 'Send sign-in code' : 'Resend code',
                    ),
                  ),
                if (!passwordMode && sentTo != null) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: code,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: const InputDecoration(labelText: 'Email code'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (code.text.trim().isEmpty) {
                              setState(
                                () =>
                                    message = 'Enter the code from your email.',
                              );
                              return;
                            }
                            unawaited(
                              run(
                                () => cloud.verifyEmailCode(sentTo!, code.text),
                              ),
                            );
                          },
                    child: const Text('Verify code'),
                  ),
                ],
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          passwordMode = !passwordMode;
                          password.clear();
                          code.clear();
                          sentTo = null;
                          message = null;
                        }),
                  child: Text(
                    passwordMode
                        ? 'Use an email code instead'
                        : 'Use a password instead',
                  ),
                ),
              ],
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (message case final notice?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(notice)),
          ),
      ],
    );
  }
}
