import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppPolicyLinks extends StatelessWidget {
  const AppPolicyLinks({super.key});

  Future<void> _open(BuildContext context, String page) async {
    try {
      if (await launchUrl(Uri.https('www.crispycrust.app', '/mobile/$page'), mode: LaunchMode.externalApplication)) return;
    } catch (_) { /* Keep the current app screen and offer the support contact. */ }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Couldn’t open this page. Contact hello@leymora.com for help.')));
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
    for (final entry in const {'privacy': 'Privacy', 'terms': 'Terms', 'support': 'Support'}.entries)
      TextButton(onPressed: () => _open(context, entry.key), child: Text(entry.value)),
  ]);
}
