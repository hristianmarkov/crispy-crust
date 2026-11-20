import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

enum KitchenTab { starters, recipes, home, features, journal }

class AppAnalytics {
  AppAnalytics(this._hasConsent);

  static const _token = String.fromEnvironment('POSTHOG_PROJECT_TOKEN');
  static const _host = String.fromEnvironment('POSTHOG_HOST');

  static bool get isConfigured {
    final uri = Uri.tryParse(_host);
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
        _token.startsWith('phc_') &&
        uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
        uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment;
  }

  final bool Function() _hasConsent;
  final _sdk = Posthog();
  Future<void> _pending = Future.value();
  bool _initialized = false;
  bool _enabled = false;
  bool _reportedOpen = false;

  Future<void> updateConsent() => _enqueue(() async {
    final desired = isConfigured && _hasConsent();
    if (desired == _enabled) return;
    if (!desired) {
      await _sdk.optOut();
      _enabled = false;
      return;
    }

    if (!_initialized) {
      await _sdk.setup(PostHogConfig(_token)
        ..host = _host
        ..optOut = true
        ..captureApplicationLifecycleEvents = false
        ..preloadFeatureFlags = false
        ..sendFeatureFlagEvent = false
        ..surveys = false
        ..sessionReplay = false
        ..capturePushNotificationSubscriptions = false
        ..capturePushNotificationOpened = false
        ..personProfiles = PostHogPersonProfiles.never);
      _initialized = true;
    }
    if (!_hasConsent()) return;
    await _sdk.optIn();
    _enabled = true;
    if (!_reportedOpen && _hasConsent()) {
      await _capture('mobile_app_opened');
      _reportedOpen = true;
    }
  });

  Future<void> tabOpened(KitchenTab tab) => _send('mobile_tab_opened', {'tab': tab == KitchenTab.home ? 'today' : tab.name});
  Future<void> connectedServicesOpened() => _send('mobile_connected_services_opened');
  Future<void> subscriptionViewed() => _send('mobile_subscription_viewed');

  Future<void> _send(String event, [Map<String, Object> properties = const {}]) => _enqueue(() async {
    if (_enabled && _hasConsent()) await _capture(event, properties);
  });

  Future<void> _capture(String event, [Map<String, Object> properties = const {}]) =>
      _sdk.capture(eventName: event, properties: {...properties, r'$geoip_disable': true});

  Future<void> _enqueue(Future<void> Function() action) =>
      _pending = _pending.then((_) async {
        try {
          await action();
        } on Object {
          // Analytics must never interrupt local baking or account access.
        }
      });
}
