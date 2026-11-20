import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
  static final shared = CloudSessionService();
  static const redirect = 'app.crispycrust://auth/callback';
  static const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const _appleBrowserEnabled = bool.fromEnvironment('APPLE_BROWSER_SIGN_IN_ENABLED');
  Future<CapabilityResult<bool>>? _connecting;
  Future<void>? _googleInitialization;
  SupabaseClient? _client;
  SupabaseClient? get client => _client;
  bool get signedIn => _client?.auth.currentUser != null;
  Stream<AuthState>? get authChanges => _client?.auth.onAuthStateChange;
  bool get supportsAppleSignIn => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get supportsAppleBrowserSignIn => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get appleBrowserSignInConfigured => supportsAppleBrowserSignIn && _appleBrowserEnabled;
  bool get supportsGoogleSignIn => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool get googleSignInConfigured => supportsGoogleSignIn && _googleWebClientId.isNotEmpty &&
      (defaultTargetPlatform != TargetPlatform.iOS || _googleIosClientId.isNotEmpty);

  /// Call only when the user chooses cloud services. Library sync stays off.
  Future<CapabilityResult<bool>> connect(CloudConfiguration configuration) {
    return _connecting ??= _connect(configuration).whenComplete(() => _connecting = null);
  }

  Future<CapabilityResult<bool>> _connect(CloudConfiguration configuration) async {
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
  Future<void> signInWithPassword(String email, String password) async {
    await _requireClient().auth.signInWithPassword(email: email.trim(), password: password);
  }
  Future<bool> signInWithApple() async {
    final auth = _requireClient().auth;
    if (!supportsAppleSignIn || !await SignInWithApple.isAvailable()) {
      throw const AuthException('Sign in with Apple is unavailable on this device.');
    }
    final rawNonce = auth.generateRawNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Apple did not return a sign-in token.');
      }
      await auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken, nonce: rawNonce);
      return true;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return false;
      throw const AuthException('Apple sign-in could not complete. Check your Apple account or try again.');
    }
  }

  Future<void> signInWithAppleInBrowser() async {
    if (!appleBrowserSignInConfigured) {
      throw const AuthException('Apple browser sign-in is unavailable in this build.');
    }
    await _requireClient().auth.signInWithOAuth(OAuthProvider.apple, redirectTo: redirect);
  }

  Future<bool> signInWithGoogle() async {
    final auth = _requireClient().auth;
    if (!googleSignInConfigured) {
      throw const AuthException('Google sign-in is unavailable in this build.');
    }
    final google = GoogleSignIn.instance;
    const scopes = ['email', 'profile'];
    try {
      await (_googleInitialization ??= google.initialize(
        serverClientId: _googleWebClientId,
        clientId: defaultTargetPlatform == TargetPlatform.iOS ? _googleIosClientId : null,
      ));
      final account = await google.authenticate(scopeHint: scopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Google did not return a sign-in token.');
      }
      final authorization = await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      await auth.signInWithIdToken(
        provider: OAuthProvider.google, idToken: idToken, accessToken: authorization.accessToken,
      );
      return true;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        // Credential Manager also reports some Android configuration errors as cancelled.
        if (defaultTargetPlatform != TargetPlatform.android) return false;
        throw const AuthException('Google sign-in didn’t finish. Try again with your Google Play testing account, or use email.');
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw const AuthException('Google rejected this app’s sign-in configuration.');
      }
      throw const AuthException('Google sign-in could not complete. Try again or use an email code.');
    }
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
    final initialized = _googleInitialization;
    if (initialized != null) {
      try {
        await initialized;
      } on Object {
        // There is no Google session to clear if SDK initialization failed.
        return;
      }
      await GoogleSignIn.instance.signOut();
    }
  }
  SupabaseClient _requireClient() => _client ?? (throw StateError('Cloud account is not configured'));
}
