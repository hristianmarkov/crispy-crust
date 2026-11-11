import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'platform_result.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage({required this.namespace,
    this.vault = const FlutterSecureStorage()});
  final String namespace;
  final FlutterSecureStorage vault;
  String get key => 'crispy-crust.auth.$namespace';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await vault.containsKey(key: key);
  @override
  Future<String?> accessToken() => vault.read(key: key);
  @override
  Future<void> persistSession(String persistSessionString) => vault.write(key: key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => vault.delete(key: key);
}

/// Configuration contains only the public project identity. No service/model keys.
class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this.namespace);
  final String namespace;
  final FlutterSecureStorage vault = const FlutterSecureStorage();
  String _key(String key) => 'crispy-crust.pkce.$namespace.$key';
  @override
  Future<String?> getItem({required String key}) => vault.read(key: _key(key));
  @override
  Future<void> setItem({required String key, required String value}) => vault.write(key: _key(key), value: value);
  @override
  Future<void> removeItem({required String key}) => vault.delete(key: _key(key));
}

class CloudConfiguration {
  const CloudConfiguration({required this.url, required this.publishableKey});
  const CloudConfiguration.fromEnvironment()
      : url = const String.fromEnvironment('SUPABASE_URL'),
        publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url;
  final String publishableKey;
  bool get isConfigured {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
      uri.userInfo.isEmpty && publishableKey.isNotEmpty && !publishableKey.startsWith('sb_secret_');
  }
}

class CloudSessionService {
  static const redirect = 'app.crispycrust://auth/callback';
  SupabaseClient? _client;
  SupabaseClient? get client => _client;
  bool get signedIn => _client?.auth.currentUser != null;
  Stream<AuthState>? get authChanges => _client?.auth.onAuthStateChange;

  /// Call only when the user chooses cloud services. Library sync stays off.
  Future<CapabilityResult<bool>> connect(CloudConfiguration configuration) async {
    if (!configuration.isConfigured) { return const CapabilityResult(
      CapabilityStatus.unconfigured,
      'Cloud services need an app backend configuration. Local baking remains available.'); }
    if (_client != null) { return const CapabilityResult.available(true); }
    final namespace = Uri.parse(configuration.url).host;
    final instance = await Supabase.initialize(url: configuration.url,
      publishableKey: configuration.publishableKey, debug: false,
      authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce,
        localStorage: SecureSessionStorage(namespace: namespace),
        pkceAsyncStorage: SecurePkceStorage(namespace),
        detectSessionInUriPredicate: isAllowedAuthRedirect));
    _client = instance.client;
    return const CapabilityResult.available(true,
      'Cloud account enabled. Library backup is still off until separately selected.');
  }

  static bool isAllowedAuthRedirect(Uri uri) => uri.scheme == 'app.crispycrust' &&
    uri.host == 'auth' && !uri.hasPort && uri.path == '/callback' && uri.userInfo.isEmpty;

  Future<void> sendEmailCode(String email) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(email: email.trim(), emailRedirectTo: redirect);
  }
  Future<void> verifyEmailCode(String email, String code) async {
    await _requireClient().auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);
  }
  Future<void> signInWithApple() => _oauth(OAuthProvider.apple);
  Future<void> signInWithGoogle() => _oauth(OAuthProvider.google);
  Future<void> _oauth(OAuthProvider provider) async {
    await _requireClient().auth.signInWithOAuth(provider, redirectTo: redirect);
  }
  Future<void> signOut() async { await _client?.auth.signOut(); }
  SupabaseClient _requireClient() => _client ?? (throw StateError('Cloud account is not configured'));
}
