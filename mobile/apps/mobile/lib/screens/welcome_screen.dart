import 'package:flutter/material.dart';

import '../platform/cloud_session.dart';
import 'account_sign_in.dart';
import 'kitchen_design.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  final Future<void> Function() onContinue;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool saving = false;
  bool saveFailed = false;

  Future<void> finish() async {
    if (saving) return;
    setState(() {
      saving = true;
      saveFailed = false;
    });
    try {
      await widget.onContinue();
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          saveFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const KitchenBrandMark(size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Crispy Crust',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1.7,
                      child: Image.asset(
                        'assets/brand/welcome-loaf.webp',
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(children: [
                    Expanded(child: Text('Feed your starter, follow a recipe and save your bakes.')),
                    SizedBox(width: 12),
                    CrumbArt(size: 66),
                  ]),
                  FilledButton(
                    onPressed: saving ? null : finish,
                    child: const Text('Continue locally'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in for shared kitchens or cloud backup.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AccountSignIn(
                    cloud: CloudSessionService.shared,
                    onSignedIn: finish,
                  ),
                  if (saveFailed)
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Could not save your preference. Tap Continue locally to try again.',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
