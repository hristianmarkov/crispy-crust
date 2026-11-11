import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SubscriptionConfiguration {
  const SubscriptionConfiguration({this.iosKey = '', this.androidKey = ''});
  const SubscriptionConfiguration.fromEnvironment()
    : iosKey = const String.fromEnvironment('REVENUECAT_IOS_PUBLIC_SDK_KEY'),
      androidKey = const String.fromEnvironment('REVENUECAT_ANDROID_PUBLIC_SDK_KEY');
  final String iosKey, androidKey;
  String? keyFor(TargetPlatform platform) {
    if (platform == TargetPlatform.iOS && iosKey.startsWith('appl_') && iosKey.length > 10) { return iosKey; }
    if (platform == TargetPlatform.android && androidKey.startsWith('goog_') && androidKey.length > 10) { return androidKey; }
    return null;
  }
}

class SubscriptionFailure implements Exception {
  const SubscriptionFailure(this.code, this.message);
  final String code, message;
  @override String toString() => '$message ($code)';
}

class StoreOffering {
  const StoreOffering({required this.id, required this.productId, required this.title,
    required this.description, required this.price, required this.period});
  final String id, productId, title, description, price, period;
  String get priceDescription => '$price / ${billingPeriodDescription(period)}';
}

String billingPeriodDescription(String value) {
  final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(value);
  if (match == null) { return 'store period $value'; }
  final count = int.parse(match.group(1)!);
  final unit = {'D': 'day', 'W': 'week', 'M': 'month', 'Y': 'year'}[match.group(2)]!;
  return count == 1 ? unit : '$count ${unit}s';
}

class VerifiedServiceEntitlement {
  const VerifiedServiceEntitlement(this.key, this.state, this.validUntil);
  final String key, state;
  final DateTime? validUntil;
}

class VerifiedSubscriptionStatus {
  const VerifiedSubscriptionStatus({required this.verifiedAt, required this.entitlements});
  final DateTime verifiedAt;
  final List<VerifiedServiceEntitlement> entitlements;
  factory VerifiedSubscriptionStatus.fromServer(Map<String, dynamic> data) {
    final date = DateTime.tryParse('${data['verified_at'] ?? ''}');
    if (data['source'] != 'revenuecat_server' || date == null || data['entitlements'] is! List) {
      throw const SubscriptionFailure('UNVERIFIED_RESPONSE', 'The service did not return a verified subscription status.');
    }
    final rows = <VerifiedServiceEntitlement>[];
    for (final row in data['entitlements'] as List) {
      if (row is! Map || row['key'] is! String || row['state'] is! String) {
        throw const SubscriptionFailure('UNVERIFIED_RESPONSE', 'The entitlement response was incomplete.');
      }
      final until = row['valid_until'] == null ? null : DateTime.tryParse('${row['valid_until']}');
      if (row['valid_until'] != null && until == null) {
        throw const SubscriptionFailure('UNVERIFIED_RESPONSE', 'The entitlement expiry was unreadable.');
      }
      rows.add(VerifiedServiceEntitlement(row['key'] as String, row['state'] as String, until));
    }
    return VerifiedSubscriptionStatus(verifiedAt: date, entitlements: List.unmodifiable(rows));
  }
}

abstract interface class SubscriptionVerifier {
  Future<VerifiedSubscriptionStatus> refresh(String expectedUserId);
}

class AuthenticatedSubscriptionVerifier implements SubscriptionVerifier {
  AuthenticatedSubscriptionVerifier({required this.client, required this.apiBase, http.Client? transport})
    : transport = transport ?? http.Client() {
    if (apiBase.scheme != 'https' || apiBase.host.isEmpty || apiBase.userInfo.isNotEmpty || apiBase.hasQuery || apiBase.hasFragment) {
      throw ArgumentError('Trusted HTTPS app API base required');
    }
  }
  final SupabaseClient client;
  final Uri apiBase;
  final http.Client transport;
  @override
  Future<VerifiedSubscriptionStatus> refresh(String expectedUserId) async {
    final session = client.auth.currentSession;
    if (session == null || client.auth.currentUser?.id != expectedUserId) {
      throw const SubscriptionFailure('ACCOUNT_CHANGED', 'Sign in to the intended app account before verifying purchases.');
    }
    final uri = Uri.parse('${apiBase.toString().replaceFirst(RegExp(r'/+$'), '')}/purchases/verify');
    final request = http.Request('POST', uri)..followRedirects = false;
    request.headers.addAll({'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json', 'Idempotency-Key': const Uuid().v4()});
    request.body = jsonEncode({'app_user_id': expectedUserId});
    final response = await transport.send(request).timeout(const Duration(seconds: 20));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 256 * 1024) { throw const SubscriptionFailure('INVALID_RESPONSE', 'Subscription response was too large.'); }
    }
    if (client.auth.currentUser?.id != expectedUserId) {
      throw const SubscriptionFailure('ACCOUNT_CHANGED', 'Account changed. Refresh this screen for the current account.');
    }
    final dynamic decoded;
    try { decoded = jsonDecode(utf8.decode(bytes)); }
    catch (_) { throw const SubscriptionFailure('INVALID_RESPONSE', 'Subscription verification returned an unreadable response.'); }
    if (decoded is! Map) { throw const SubscriptionFailure('INVALID_RESPONSE', 'Subscription verification returned an invalid response.'); }
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['error'] != null) {
      final error = decoded['error'];
      final code = error is Map ? '${error['code'] ?? 'VERIFICATION_UNAVAILABLE'}' : 'VERIFICATION_UNAVAILABLE';
      throw SubscriptionFailure(code, code == 'STORE_VERIFICATION_NOT_CONFIGURED'
        ? 'Subscription verification is not configured on the app backend. Purchases are unavailable.'
        : 'The server could not verify subscription status. Local baking remains available.');
    }
    if (decoded['data'] is! Map) { throw const SubscriptionFailure('INVALID_RESPONSE', 'The verification result was incomplete.'); }
    return VerifiedSubscriptionStatus.fromServer(Map<String, dynamic>.from(decoded['data'] as Map));
  }
  void close() => transport.close();
}

abstract interface class SubscriptionStoreGateway {
  Future<void> bind(String publicKey, String userId);
  Future<List<StoreOffering>> offerings(String expectedUserId);
  Future<void> purchase(String expectedUserId, String offeringId);
  Future<void> restore(String expectedUserId);
  Future<String?> managementUrl(String expectedUserId);
  Future<void> signOut();
}

class RevenueCatStoreGateway implements SubscriptionStoreGateway {
  static Future<void> _queue = Future.value();
  static String? _configuredKey;
  static SupabaseClient? _authClient;
  static StreamSubscription<AuthState>? _authSubscription;
  static String? _observedAuthUser;
  final _packages = <String, Package>{};

  /// Keep account cleanup active after a settings screen closes. This guard
  /// never configures the SDK or makes an anonymous purchase; it only removes
  /// a previously bound identity when the authenticated app identity changes.
  static void attachAuthentication(SupabaseClient client) {
    if (identical(_authClient, client)) { return; }
    unawaited(_authSubscription?.cancel());
    _authClient = client;
    _observedAuthUser = client.auth.currentUser?.id;
    _authSubscription = client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user.id;
      if (user == _observedAuthUser) { return; }
      _observedAuthUser = user;
      unawaited(_serialized<void>(() async {
        if (await Purchases.isConfigured && !await Purchases.isAnonymous) {
          await Purchases.logOut();
        }
      }).catchError((Object _) { /* UI/service actions still require matching authenticated identity. */ }));
    });
  }

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try { result.complete(await action()); }
      catch (error, stack) { result.completeError(error, stack); }
    });
    return result.future;
  }
  Future<void> _assertIdentity(String userId) async {
    if (await Purchases.appUserID != userId) {
      throw const SubscriptionFailure('ACCOUNT_CHANGED', 'Store identity changed. Refresh for the current app account.');
    }
  }
  @override
  Future<void> bind(String publicKey, String userId) => _serialized(() async {
    _packages.clear();
    await Purchases.setLogLevel(LogLevel.error);
    if (!await Purchases.isConfigured) {
      final configuration = PurchasesConfiguration(publicKey)
        ..appUserID = userId
        ..automaticDeviceIdentifierCollectionEnabled = false
        ..diagnosticsEnabled = false
        ..shouldShowInAppMessagesAutomatically = false;
      await Purchases.configure(configuration);
      _configuredKey = publicKey;
    } else {
      if (_configuredKey != publicKey) {
        throw const SubscriptionFailure('SDK_CONFIGURATION_CHANGED', 'Store configuration changed. Restart the app before using purchases.');
      }
      if (await Purchases.appUserID != userId) { await Purchases.logIn(userId); }
    }
    await _assertIdentity(userId);
  });
  @override
  Future<List<StoreOffering>> offerings(String expectedUserId) => _serialized(() async {
    await _assertIdentity(expectedUserId);
    final result = await Purchases.getOfferings();
    await _assertIdentity(expectedUserId);
    _packages.clear();
    final rows = <StoreOffering>[];
    for (final package in result.current?.availablePackages ?? <Package>[]) {
      final product = package.storeProduct;
      final period = product.subscriptionPeriod;
      if (period == null || period.isEmpty) { continue; }
      _packages[package.identifier] = package;
      rows.add(StoreOffering(id: package.identifier, productId: product.identifier,
        title: product.title, description: product.description,
        price: product.priceString, period: period));
    }
    return rows;
  });
  @override
  Future<void> purchase(String expectedUserId, String offeringId) => _serialized(() async {
    await _assertIdentity(expectedUserId);
    final package = _packages[offeringId];
    if (package == null) { throw const SubscriptionFailure('OFFERING_CHANGED', 'Refresh the current store offering before purchasing.'); }
    await Purchases.purchase(PurchaseParams.package(package));
    await _assertIdentity(expectedUserId);
  });
  @override
  Future<void> restore(String expectedUserId) => _serialized(() async {
    await _assertIdentity(expectedUserId);
    await Purchases.restorePurchases();
    await _assertIdentity(expectedUserId);
  });
  @override
  Future<String?> managementUrl(String expectedUserId) => _serialized(() async {
    await _assertIdentity(expectedUserId);
    final info = await Purchases.getCustomerInfo();
    await _assertIdentity(expectedUserId);
    return info.managementURL;
  });
  @override
  Future<void> signOut() => _serialized(() async {
    _packages.clear();
    if (await Purchases.isConfigured && !await Purchases.isAnonymous) { await Purchases.logOut(); }
  });
}

Uri? validatedStoreManagementUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort) { return null; }
  if (!{'apps.apple.com', 'itunes.apple.com', 'play.google.com'}.contains(uri.host)) { return null; }
  return uri;
}

enum SubscriptionState { signedOut, unconfigured, loading, ready, failed }

class SubscriptionService extends ChangeNotifier {
  SubscriptionService({required this.currentUserId, required this.gateway, required this.verifier,
    this.configuration = const SubscriptionConfiguration.fromEnvironment(), TargetPlatform? platform})
    : platform = platform ?? defaultTargetPlatform;
  final String? Function() currentUserId;
  final SubscriptionStoreGateway gateway;
  final SubscriptionVerifier verifier;
  final SubscriptionConfiguration configuration;
  final TargetPlatform platform;
  SubscriptionState state = SubscriptionState.unconfigured;
  String message = 'Choose to refresh subscriptions. No purchase request has been made.';
  List<StoreOffering> offerings = const [];
  VerifiedSubscriptionStatus? verifiedStatus;
  Uri? managementUri;
  String? accountId;
  bool _disposed = false;
  bool _mutationQueued = false;
  int _generation = 0;
  Future<void> _queue = Future.value();
  bool get canPurchase => state == SubscriptionState.ready && verifiedStatus != null &&
    accountId != null && accountId == currentUserId();
  void _notify() { if (!_disposed) { notifyListeners(); } }
  void _clear() { offerings = const []; verifiedStatus = null; managementUri = null; accountId = null; }
  void _assertUser(String expected, int generation) {
    if (_disposed || _generation != generation || currentUserId() != expected) {
      throw const SubscriptionFailure('ACCOUNT_CHANGED', 'Account changed. No subscription state was applied to another account.');
    }
  }
  Future<void> _serialized(Future<void> Function() action) {
    final result = Completer<void>();
    _queue = _queue.then((_) async {
      try { await action(); result.complete(); }
      catch (error, stack) { result.completeError(error, stack); }
    });
    return result.future;
  }
  /// Call synchronously on every auth identity change. Previous account data is
  /// cleared before any asynchronous SDK work, including an in-flight purchase.
  Future<void> identityChanged() {
    _generation++; _clear();
    state = currentUserId() == null ? SubscriptionState.signedOut : SubscriptionState.unconfigured;
    message = currentUserId() == null ? 'Sign in to the intended app account before using purchases. Local baking remains available.'
      : 'Account changed. Refresh to load this account’s store state.';
    _notify();
    if (currentUserId() == null) { return _serialized(() async { try { await gateway.signOut(); } catch (_) { /* All actions remain gated by signed-in identity. */ } }); }
    return Future.value();
  }
  Future<void> refresh() => _serialized(() => _perform());
  Future<void> purchase(String offeringId) {
    if (_mutationQueued || state == SubscriptionState.loading) { return Future.value(); }
    _mutationQueued = true;
    return _serialized(() => _perform(purchaseId: offeringId)).whenComplete(() => _mutationQueued = false);
  }
  Future<void> restore() {
    if (_mutationQueued || state == SubscriptionState.loading) { return Future.value(); }
    _mutationQueued = true;
    return _serialized(() => _perform(restore: true)).whenComplete(() => _mutationQueued = false);
  }

  Future<void> _perform({String? purchaseId, bool restore = false}) async {
    if (_disposed) { return; }
    final user = currentUserId();
    final generation = _generation;
    if (user == null) { _clear(); state = SubscriptionState.signedOut;
      message = 'Sign in before using purchases. Local baking and existing records remain available.'; _notify(); return; }
    final key = !kIsWeb ? configuration.keyFor(platform) : null;
    if (key == null) { _clear(); state = SubscriptionState.unconfigured;
      message = 'This platform’s public store SDK key is not configured. No prices, trials or paid access have been assumed.'; _notify(); return; }
    if (purchaseId != null && (!canPurchase || accountId != user || !offerings.any((o) => o.id == purchaseId))) {
      message = 'Refresh a server-verified status and current store offering before purchasing.'; _notify(); return;
    }
    state = SubscriptionState.loading; message = 'Checking store and service status…'; _notify();
    try {
      await gateway.bind(key, user); _assertUser(user, generation);
      // bind invalidates package handles, so reload before purchasing.
      final currentOfferings = await gateway.offerings(user); _assertUser(user, generation);
      if (purchaseId != null) {
        if (!currentOfferings.any((o) => o.id == purchaseId)) { throw const SubscriptionFailure('OFFERING_CHANGED', 'The offering changed. Review current store prices before buying.'); }
        await gateway.purchase(user, purchaseId); _assertUser(user, generation);
      }
      if (restore) { await gateway.restore(user); _assertUser(user, generation); }
      final management = await gateway.managementUrl(user); _assertUser(user, generation);
      VerifiedSubscriptionStatus? verified;
      String? verificationMessage;
      try { verified = await verifier.refresh(user); _assertUser(user, generation); }
      on SubscriptionFailure catch (error) { if (error.code == 'ACCOUNT_CHANGED') { rethrow; } verificationMessage = error.message; }
      _assertUser(user, generation);
      accountId = user; offerings = List.unmodifiable(currentOfferings);
      managementUri = validatedStoreManagementUri(management); verifiedStatus = verified;
      state = SubscriptionState.ready;
      message = verificationMessage ?? (restore ? 'Restore completed and service status verified.' : purchaseId != null
        ? 'Store purchase completed and service status verified.' : currentOfferings.isEmpty
          ? 'No subscription offering was returned by this store. No product or price has been invented.' : 'Current store offerings and service status loaded.');
      _notify();
    } catch (error) {
      if (_disposed || generation != _generation || currentUserId() != user) { return; }
      _clear(); state = SubscriptionState.failed;
      if (error is PlatformException && PurchasesErrorHelper.getErrorCode(error) == PurchasesErrorCode.purchaseCancelledError) {
        message = 'Purchase canceled. Local baking and your records are unchanged.';
      } else if (error is SubscriptionFailure) { message = error.message; }
      else { message = 'The store request could not be completed. No local access was unlocked. Refresh or restore when available.'; }
      _notify();
    }
  }
  @override void dispose() { _disposed = true; _generation++; _clear(); super.dispose(); }
}
