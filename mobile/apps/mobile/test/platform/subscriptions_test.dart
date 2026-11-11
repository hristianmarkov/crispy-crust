import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/platform/subscriptions.dart';
import 'package:crispy_crust/screens/subscription_screen.dart';

const offer = StoreOffering(id: 'actual-monthly', productId: 'store.product.monthly',
  title: 'Store fixture title', description: 'Store fixture description', price: '£3.49', period: 'P1M');

class FakeStore implements SubscriptionStoreGateway {
  int bindings = 0, purchases = 0, restores = 0, logouts = 0;
  String? boundUser;
  List<StoreOffering> products = [offer];
  Completer<void>? bindGate;
  Completer<void>? purchaseGate;
  String? manage = 'https://apps.apple.com/account/subscriptions';
  @override Future<void> bind(String publicKey, String userId) async {
    bindings++;
    await bindGate?.future;
    boundUser = userId;
  }
  @override Future<List<StoreOffering>> offerings(String expectedUserId) async {
    expect(boundUser, expectedUserId); return products;
  }
  @override Future<void> purchase(String expectedUserId, String offeringId) async {
    expect(boundUser, expectedUserId); expect(offeringId, offer.id); purchases++;
    await purchaseGate?.future;
  }
  @override Future<void> restore(String expectedUserId) async { expect(boundUser, expectedUserId); restores++; }
  @override Future<String?> managementUrl(String expectedUserId) async { expect(boundUser, expectedUserId); return manage; }
  @override Future<void> signOut() async { boundUser = null; logouts++; }
}

class FakeVerifier implements SubscriptionVerifier {
  final checkedUsers = <String>[];
  bool unavailable = false;
  @override Future<VerifiedSubscriptionStatus> refresh(String expectedUserId) async {
    checkedUsers.add(expectedUserId);
    if (unavailable) { throw const SubscriptionFailure('STORE_VERIFICATION_NOT_CONFIGURED', 'Billing verification is not configured.'); }
    return VerifiedSubscriptionStatus.fromServer({'source': 'revenuecat_server',
      'verified_at': '2026-11-11T12:00:00Z', 'entitlements': <Map<String, dynamic>>[]});
  }
}

void main() {
  const configured = SubscriptionConfiguration(androidKey: 'goog_public_sdk_fixture');
  test('anonymous/local-only mode never configures or purchases from the store', () async {
    final store = FakeStore(); final verifier = FakeVerifier();
    final service = SubscriptionService(currentUserId: () => null, gateway: store,
      verifier: verifier, configuration: configured, platform: TargetPlatform.android);
    await service.refresh(); await service.restore(); await service.purchase('invented');
    expect(service.state, SubscriptionState.signedOut);
    expect(store.bindings, 0); expect(store.purchases, 0); expect(store.restores, 0);
    expect(verifier.checkedUsers, isEmpty); service.dispose();
  });
  test('missing or secret-like public key never initializes SDK or invents offerings', () async {
    final store = FakeStore();
    final service = SubscriptionService(currentUserId: () => 'user-a', gateway: store,
      verifier: FakeVerifier(), configuration: const SubscriptionConfiguration(androidKey: 'sk_secret_fixture'),
      platform: TargetPlatform.android);
    await service.refresh(); expect(service.state, SubscriptionState.unconfigured);
    expect(service.offerings, isEmpty); expect(store.bindings, 0); service.dispose();
    expect(const SubscriptionConfiguration(iosKey: 'goog_wrong_platform').keyFor(TargetPlatform.iOS), isNull);
  });
  test('actual store offering retained; purchases and restores reverify the bound account', () async {
    final store = FakeStore(); final verifier = FakeVerifier();
    final service = SubscriptionService(currentUserId: () => 'user-a', gateway: store,
      verifier: verifier, configuration: configured, platform: TargetPlatform.android);
    await service.refresh(); expect(service.offerings.single.priceDescription, '£3.49 / month');
    expect(service.canPurchase, isTrue);
    await service.purchase(offer.id); expect(store.purchases, 1);
    await service.restore(); expect(store.restores, 1);
    expect(verifier.checkedUsers, ['user-a', 'user-a', 'user-a']);
    expect(service.verifiedStatus!.entitlements, isEmpty);
    expect(service.managementUri!.host, 'apps.apple.com'); service.dispose();
  });
  test('rapid duplicate purchase calls initiate only one store purchase', () async {
    final store = FakeStore()..purchaseGate = Completer<void>();
    final service = SubscriptionService(currentUserId: () => 'user-a', gateway: store,
      verifier: FakeVerifier(), configuration: configured, platform: TargetPlatform.android);
    await service.refresh();
    final first = service.purchase(offer.id);
    await service.purchase(offer.id);
    await Future<void>.delayed(Duration.zero);
    store.purchaseGate!.complete(); await first;
    expect(store.purchases, 1); service.dispose();
  });
  test('client cannot purchase when server verification is unavailable', () async {
    final store = FakeStore(); final verifier = FakeVerifier()..unavailable = true;
    final service = SubscriptionService(currentUserId: () => 'user-a', gateway: store,
      verifier: verifier, configuration: configured, platform: TargetPlatform.android);
    await service.refresh(); expect(service.offerings.single.title, offer.title);
    expect(service.verifiedStatus, isNull); expect(service.canPurchase, isFalse);
    await service.purchase(offer.id); expect(store.purchases, 0); service.dispose();
  });
  test('account switch clears previous state before asynchronous store work completes', () async {
    var current = 'user-a';
    final store = FakeStore()..bindGate = Completer<void>(); final verifier = FakeVerifier();
    final service = SubscriptionService(currentUserId: () => current, gateway: store,
      verifier: verifier, configuration: configured, platform: TargetPlatform.android);
    final loading = service.refresh(); await Future<void>.delayed(Duration.zero);
    current = 'user-b'; await service.identityChanged();
    expect(service.offerings, isEmpty); expect(service.verifiedStatus, isNull); expect(service.accountId, isNull);
    store.bindGate!.complete(); await loading;
    expect(service.offerings, isEmpty); expect(verifier.checkedUsers, isEmpty);
    await service.refresh(); expect(service.accountId, 'user-b'); expect(store.boundUser, 'user-b');
    expect(verifier.checkedUsers, ['user-b']); service.dispose();
  });
  test('sign-out clears state and logs SDK out without anonymous purchasing', () async {
    String? current = 'user-a'; final store = FakeStore();
    final service = SubscriptionService(currentUserId: () => current, gateway: store,
      verifier: FakeVerifier(), configuration: configured, platform: TargetPlatform.android);
    await service.refresh(); current = null;
    final clearing = service.identityChanged();
    expect(service.offerings, isEmpty); expect(service.managementUri, isNull); expect(service.verifiedStatus, isNull);
    await clearing; expect(store.logouts, 1); await service.restore(); expect(store.restores, 0); service.dispose();
  });
  test('local or malformed status cannot masquerade as a verified entitlement', () {
    expect(() => VerifiedSubscriptionStatus.fromServer({'source': 'client',
      'verified_at': '2026-11-11T12:00:00Z', 'entitlements': [{'key': 'pro', 'state': 'active'}]}), throwsA(isA<SubscriptionFailure>()));
    expect(() => VerifiedSubscriptionStatus.fromServer({'source': 'revenuecat_server',
      'verified_at': 'invalid', 'entitlements': []}), throwsA(isA<SubscriptionFailure>()));
    expect(validatedStoreManagementUri('https://store-attacker.test/checkout'), isNull);
    expect(validatedStoreManagementUri('https://apps.apple.com@attacker.test/'), isNull);
    expect(validatedStoreManagementUri('http://apps.apple.com/account/subscriptions'), isNull);
    expect(validatedStoreManagementUri('https://play.google.com/store/account/subscriptions')?.host, 'play.google.com');
  });
  testWidgets('unconfigured screen shows no placeholder product or purchase button', (tester) async {
    final store = FakeStore();
    final service = SubscriptionService(currentUserId: () => null, gateway: store,
      verifier: FakeVerifier(), platform: TargetPlatform.android);
    await tester.pumpWidget(MaterialApp(home: SubscriptionScreen(client: null, apiBase: null, service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Subscriptions and purchases'), findsOneWidget);
    expect(find.text('Review purchase in store'), findsNothing);
    expect(store.bindings, 0);
    await tester.pumpWidget(const SizedBox()); service.dispose();
  });
}
