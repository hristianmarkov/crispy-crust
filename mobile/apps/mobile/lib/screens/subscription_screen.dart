import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../platform/subscriptions.dart';

class _UnavailableVerifier implements SubscriptionVerifier {
  @override
  Future<VerifiedSubscriptionStatus> refresh(String expectedUserId) async {
    throw const SubscriptionFailure('BILLING_API_NOT_CONFIGURED',
      'The authenticated billing service is not configured. Purchases are unavailable.');
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.client, required this.apiBase, this.service});
  final SupabaseClient? client;
  final Uri? apiBase;
  final SubscriptionService? service;
  @override State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final SubscriptionService service;
  AuthenticatedSubscriptionVerifier? verifier;
  StreamSubscription<AuthState>? authSubscription;
  String? observedUserId;
  String? localMessage;

  @override void initState() {
    super.initState();
    final client = widget.client;
    observedUserId = client?.auth.currentUser?.id;
    if (widget.service != null) { service = widget.service!; }
    else {
      if (client != null) { RevenueCatStoreGateway.attachAuthentication(client); }
      if (client != null && widget.apiBase != null) {
        verifier = AuthenticatedSubscriptionVerifier(client: client, apiBase: widget.apiBase!);
      }
      service = SubscriptionService(currentUserId: () => client?.auth.currentUser?.id,
        gateway: RevenueCatStoreGateway(), verifier: verifier ?? _UnavailableVerifier());
    }
    service.addListener(refreshView);
    authSubscription = client?.auth.onAuthStateChange.listen((event) {
      final userId = event.session?.user.id;
      if (userId != observedUserId) {
        observedUserId = userId;
        unawaited(service.identityChanged());
      }
    });
    unawaited(service.refresh());
  }

  void refreshView() { if (mounted) { setState(() {}); } }
  @override void dispose() {
    unawaited(authSubscription?.cancel());
    service.removeListener(refreshView);
    if (widget.service == null) { service.dispose(); }
    verifier?.close();
    super.dispose();
  }
  Future<bool> confirm(String title, String body, String action) async =>
    await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ])) ?? false;

  Future<void> purchase(StoreOffering offer) async {
    if (!await confirm('Review store purchase',
      '${offer.title}\n${offer.priceDescription}\n\n${offer.description}\n\n'
      'This uses the signed-in app account. The App Store or Google Play confirmation shows the final applicable terms. '
      'No free trial is promised here. You can cancel before approving the store purchase.', 'Continue to store')) { return; }
    await service.purchase(offer.id);
  }
  Future<void> restore() async {
    final expectedUser = service.currentUserId();
    if (!await confirm('Restore purchases to this account?',
      'Check that you are signed in to the intended app account and the store account that made the purchase. '
      'This contacts the store and verifies the result with Crispy Crust. It does not create a new purchase. '
      'Store-account transfer rules depend on the configured service policy.', 'Restore purchases')) { return; }
    if (expectedUser == null || service.currentUserId() != expectedUser) {
      if (mounted) { setState(() => localMessage = 'Account changed. Review restore again for the current app account.'); }
      return;
    }
    await service.restore();
  }
  Future<void> manage() async {
    final uri = service.managementUri;
    if (uri == null || service.currentUserId() != service.accountId) { return; }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) { setState(() => localMessage = 'The store subscription settings could not be opened. Use your store account’s subscription settings.'); }
    } catch (_) {
      if (mounted) { setState(() => localMessage = 'The store settings link is unavailable on this device.'); }
    }
  }

  @override Widget build(BuildContext context) {
    final busy = service.state == SubscriptionState.loading;
    final signedIn = widget.client?.auth.currentUser != null || service.accountId != null;
    final status = service.verifiedStatus;
    return Scaffold(appBar: AppBar(title: const Text('Subscriptions and purchases')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Your store account, clearly.', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('Core local baking and your saved records remain available. Opening subscription settings never changes an active bake or starts a purchase.'),
        const SizedBox(height: 12),
        const Text('Store services use your app account ID and purchase information. Private bakes, photos and calendar details are not attached. No advertising identifiers are intentionally collected by this integration.'),
        const SizedBox(height: 20),
        if (!signedIn) const Text('Sign in through Cloud services before buying or restoring. Purchases are unavailable while signed out; local baking does not require signing in.'),
        if (widget.client?.auth.currentUser?.email case final String email) Text('App account: $email'),
        if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
        Semantics(liveRegion: true, child: Text(service.message)),
        if (localMessage != null) Text(localMessage!),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: busy ? null : service.refresh,
          icon: const Icon(Icons.refresh), label: const Text('Refresh store and verified service status')),
        const SizedBox(height: 24),
        Text('Verified service status', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (status == null) const Text('Service access has not been verified. Local baking and existing records remain available.'),
        if (status != null) ...[
          Text('Server verified ${status.verifiedAt.toLocal()}'),
          if (status.entitlements.isEmpty) const Text('No service entitlement was returned by the verified provider snapshot.'),
          for (final entitlement in status.entitlements) ListTile(contentPadding: EdgeInsets.zero,
            title: Text(entitlement.key), subtitle: Text('${entitlement.state}'
              '${entitlement.validUntil == null ? '' : ' · until ${entitlement.validUntil!.toLocal()}'}')),
        ],
        const SizedBox(height: 24),
        Text('Current store offering', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (service.offerings.isEmpty) const Text('No configured subscription product is available to show. Prices and trials are not placeholders.'),
        for (final offer in service.offerings) Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(offer.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8), Text(offer.description),
            const SizedBox(height: 8), Text(offer.priceDescription, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy || !service.canPurchase ? null : () => purchase(offer),
              child: const Text('Review purchase in store')),
          ]))),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: busy || !signedIn || service.state == SubscriptionState.unconfigured ? null : restore,
          child: const Text('Restore purchases')),
        if (service.managementUri != null) OutlinedButton.icon(onPressed: busy ? null : manage,
          icon: const Icon(Icons.open_in_new), label: const Text('Manage subscription in the store')),
        const SizedBox(height: 20),
        const Text('Cancellation and account deletion are separate actions. Manage a subscription in the store where it was purchased. '
          'Deleting app data does not automatically cancel a subscription. Exports and your existing local records remain available.'),
      ]));
  }
}
