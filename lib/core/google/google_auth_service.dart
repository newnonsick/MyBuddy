import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:http/http.dart' as http;

/// Configuration for Google Sign-In client IDs.
///
/// Pass these at build time using --dart-define:
/// ```
/// flutter run --dart-define=GOOGLE_CLIENT_ID_ANDROID=your-android-client-id
/// flutter run --dart-define=GOOGLE_CLIENT_ID_WEB=your-web-client-id
/// flutter run --dart-define=GOOGLE_CLIENT_ID_IOS=your-ios-client-id
/// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=your-server-client-id
/// ```
abstract class GoogleAuthConfig {
  /// Android client ID (required for Android without google-services.json).
  static const String androidClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_ANDROID',
    defaultValue: '',
  );

  static const String webClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_WEB',
    defaultValue: '',
  );

  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_IOS',
    defaultValue: '',
  );

  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static String? get clientId {
    if (kIsWeb) {
      return webClientId.isNotEmpty ? webClientId : null;
    }
    if (!kIsWeb && Platform.isAndroid) {
      return androidClientId.isNotEmpty ? androidClientId : null;
    }
    if (!kIsWeb && Platform.isIOS) {
      return iosClientId.isNotEmpty ? iosClientId : null;
    }
    return null;
  }
}

enum GoogleAuthState {
  signedOut,
  signingIn,
  signedIn,
  error,
}

class GoogleAuthService extends ChangeNotifier {
  GoogleAuthService() {
    _initFuture = _init();
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  late final Future<void> _initFuture;

  Future<void> ensureInitialized() => _initFuture;

  GoogleAuthState _state = GoogleAuthState.signedOut;
  GoogleAuthState get state => _state;

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  http.Client? _authClient;

  http.Client? get authClient => _authClient;

  String? get userEmail => _currentUser?.email;

  String? get displayName => _currentUser?.displayName;

  String? get photoUrl => _currentUser?.photoUrl;

  bool get isSignedIn =>
      _state == GoogleAuthState.signedIn && _currentUser != null;

  bool get isLoading => _state == GoogleAuthState.signingIn;

  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  Future<void> _init() async {
    try {
      await _googleSignIn.initialize(
        clientId: GoogleAuthConfig.clientId,
        serverClientId: GoogleAuthConfig.serverClientId.isNotEmpty
            ? GoogleAuthConfig.serverClientId
            : null,
      );

      _authSubscription = _googleSignIn.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: _handleAuthenticationError,
      );

      await _tryRestoreSession();
    } catch (e) {
      debugPrint('GoogleAuthService: Init failed: $e');
      _setState(GoogleAuthState.signedOut);
    }
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(:final user):
        _handleUserSignIn(user);
      case GoogleSignInAuthenticationEventSignOut():
        _handleUserSignOut();
    }
  }

  void _handleAuthenticationError(Object error) {
    debugPrint('GoogleAuthService: Auth error: $error');
    _errorMessage = _parseError(error);
    _setState(GoogleAuthState.error);
  }

  Future<void> _handleUserSignIn(GoogleSignInAccount user) async {
    _currentUser = user;

    try {
      _authClient = await user.authorizationClient
          .authorizationForScopes([calendar.CalendarApi.calendarScope])
          .then((auth) {
            if (auth == null) return null;
            return GoogleAuthClient(auth.accessToken);
          });

      if (_authClient != null) {
        _errorMessage = null;
        _setState(GoogleAuthState.signedIn);
      } else {
        await _requestAuthorization(user);
      }
    } catch (e) {
      debugPrint('GoogleAuthService: Failed to get auth client: $e');
      _errorMessage = 'Failed to authenticate with Google';
      _setState(GoogleAuthState.error);
    }
  }

  Future<void> _requestAuthorization(GoogleSignInAccount user) async {
    try {
      final auth = await user.authorizationClient.authorizeScopes([
        calendar.CalendarApi.calendarScope,
      ]);

      _authClient = GoogleAuthClient(auth.accessToken);
      _errorMessage = null;
      _setState(GoogleAuthState.signedIn);
    } catch (e) {
      debugPrint('GoogleAuthService: Authorization failed: $e');
      _errorMessage = _parseError(e);
      _setState(GoogleAuthState.error);
    }
  }

  void _handleUserSignOut() {
    _currentUser = null;
    _authClient = null;
    _setState(GoogleAuthState.signedOut);
  }

  Future<void> _tryRestoreSession() async {
    try {
      _setState(GoogleAuthState.signingIn);

      final result = _googleSignIn.attemptLightweightAuthentication();

      if (result == null) {
        _setState(GoogleAuthState.signedOut);
        return;
      }

      final account = await result;
      if (account != null) {
        await _handleUserSignIn(account);
      } else {
        _setState(GoogleAuthState.signedOut);
      }
    } catch (e) {
      debugPrint('GoogleAuthService: Silent sign-in failed: $e');
      _setState(GoogleAuthState.signedOut);
    }
  }

  Future<bool> signIn() async {
    if (_state == GoogleAuthState.signingIn) {
      return false;
    }

    _errorMessage = null;
    _setState(GoogleAuthState.signingIn);

    try {
      if (!_googleSignIn.supportsAuthenticate()) {
        _errorMessage = 'Sign-in not supported on this platform';
        _setState(GoogleAuthState.error);
        return false;
      }

      final account = await _googleSignIn.authenticate(
        scopeHint: [calendar.CalendarApi.calendarScope],
      );

      await _handleUserSignIn(account);
      return _state == GoogleAuthState.signedIn;
    } on GoogleSignInException catch (e) {
      debugPrint('GoogleAuthService: Sign-in failed: $e');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        _setState(GoogleAuthState.signedOut);
        return false;
      }
      _errorMessage = _parseGoogleException(e);
      _setState(GoogleAuthState.error);
      return false;
    } catch (e) {
      debugPrint('GoogleAuthService: Sign-in failed: $e');
      _errorMessage = _parseError(e);
      _setState(GoogleAuthState.error);
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _authClient = null;
      _currentUser = null;
      _errorMessage = null;
      _setState(GoogleAuthState.signedOut);
    } catch (e) {
      debugPrint('GoogleAuthService: Sign-out failed: $e');
      _errorMessage = 'Failed to sign out';
      _setState(GoogleAuthState.error);
    }
  }

  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _authClient = null;
      _currentUser = null;
      _errorMessage = null;
      _setState(GoogleAuthState.signedOut);
    } catch (e) {
      debugPrint('GoogleAuthService: Disconnect failed: $e');
      _errorMessage = 'Failed to disconnect account';
      _setState(GoogleAuthState.error);
    }
  }

  Future<bool> ensureValidToken() async {
    if (_currentUser == null) {
      return false;
    }

    try {
      final auth = await _currentUser!.authorizationClient
          .authorizationForScopes([calendar.CalendarApi.calendarScope]);

      if (auth == null) {
        final newAuth = await _currentUser!.authorizationClient.authorizeScopes(
          [calendar.CalendarApi.calendarScope],
        );

        _authClient = GoogleAuthClient(newAuth.accessToken);
      } else {
        _authClient = GoogleAuthClient(auth.accessToken);
      }

      return _authClient != null;
    } catch (e) {
      debugPrint('GoogleAuthService: Token refresh failed: $e');
      _errorMessage = 'Session expired. Please sign in again.';
      _setState(GoogleAuthState.signedOut);
      return false;
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      if (_state == GoogleAuthState.error) {
        _setState(
          _currentUser != null
              ? GoogleAuthState.signedIn
              : GoogleAuthState.signedOut,
        );
      }
    }
  }

  void _setState(GoogleAuthState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  String _parseGoogleException(GoogleSignInException e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return 'Sign-in was cancelled.';
    }
    return e.description ?? 'Sign-in failed. Please try again.';
  }

  String _parseError(dynamic error) {
    final message = error.toString().toLowerCase();

    if (message.contains('network') || message.contains('socket')) {
      return 'Network error. Please check your connection.';
    }
    if (message.contains('cancel')) {
      return 'Sign-in was cancelled.';
    }
    if (message.contains('permission') || message.contains('denied')) {
      return 'Permission denied. Please grant calendar access.';
    }
    if (message.contains('invalid') || message.contains('token')) {
      return 'Authentication failed. Please try again.';
    }

    return message;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authClient?.close();
    super.dispose();
  }
}

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._accessToken);

  final String _accessToken;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}
