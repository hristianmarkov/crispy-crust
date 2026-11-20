import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../platform/subscriptions.dart';
import 'kitchen_design.dart';
import 'app_policy_links.dart';

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
      'The store shows the final terms before you confirm. Subscriptions renew unless cancelled in your store account.', 'Continue to store')) { return; }
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
    final theme = Theme.of(context);
    final busy = service.state == SubscriptionState.loading;
    final signedIn = widget.client?.auth.currentUser != null || service.accountId != null;
    final status = service.verifiedStatus;
    return Scaffold(appBar: AppBar(title: const Text('Subscriptions and purchases')),
      body: SafeArea(child: KitchenPage(children: [
        const KitchenHeading('Crispy Crust Pro',
          detail: 'Starter tracking, bake planning and your journal are available without a subscription.'),
        const SizedBox(height: 16),
        const ListTile(leading: Icon(Icons.chat_bubble_outline),
          title: Text('A little help for your next loaf'),
          subtitle: Text('Ask about your dough and the recipe step you’re on. Free includes 3 coach questions per calendar month; Pro includes 60. Sign-in and internet required.')),
        if (service.gateway is RevenueCatStoreGateway)
          FilledButton(onPressed: busy || !service.canPurchase ? null : service.showPaywall,
            child: const Text('Explore Crispy Crust Pro')),
        if (!signedIn) const Text('To buy or restore, sign in under Kitchen → Connected services.'),
        if (widget.client?.auth.currentUser?.email case final String email) Text('App account: $email'),
        if (service.configuration.keyFor(service.platform)?.startsWith('test_') == true)
          const Text('Test Store · Purchases here are simulated.'),
        if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
        if (signedIn) Semantics(liveRegion: true, child: Text(service.message)),
        if (localMessage != null) Text(localMessage!),
        if (service.offerings.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Choose a plan', style: theme.textTheme.titleLarge),
        ],
        for (final offer in service.gateway is RevenueCatStoreGateway ? <StoreOffering>[] : service.offerings) Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(offer.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8), Text(offer.priceDescription, style: theme.textTheme.titleMedium),
            if (offer.description.isNotEmpty && offer.description != offer.title) ...[
              const SizedBox(height: 8), Text(offer.description),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: busy || !service.canPurchase ? null : () => purchase(offer),
              child: const Text('Review purchase in store')),
          ]))),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: busy || !signedIn || service.state == SubscriptionState.unconfigured ? null : restore,
          child: const Text('Restore purchases')),
        if (service.managementUri != null) OutlinedButton.icon(onPressed: busy ? null : manage,
          icon: const Icon(Icons.open_in_new), label: const Text('Manage subscription in the store')),
        if (signedIn)
          TextButton.icon(onPressed: busy ? null : service.refresh,
            icon: const Icon(Icons.refresh), label: const Text('Refresh plans and access')),
        if (status != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Verified subscription access'),
            children: [
              if (status.entitlements.isEmpty) const ListTile(title: Text('No active subscription access')),
              for (final entitlement in status.entitlements)
                ListTile(
                  title: Text(entitlement.key == 'crispy_crust_pro' ? 'Crispy Crust Pro' : entitlement.key),
                  subtitle: Text(entitlement.state),
                ),
            ],
          ),
        const SizedBox(height: 12),
        const Text('Cancel through the store where you subscribed. Deleting your app account does not cancel store billing.'),
        const AppPolicyLinks(),
        if (Navigator.canPop(context))
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to baking')),
      ])));
  }
}
