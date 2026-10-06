import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../config.dart";
import "api_service.dart";

class AuthUser {
  AuthUser({required this.uid, required this.email});
  final String uid;
  final String email;
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signs users in either with Firebase Auth or with PackUP accounts stored on the API server.
class AuthService extends ChangeNotifier {
  AuthUser? current;
  String? _token;

  /// Called when the server rejects the saved session, so the app can show the login screen.
  VoidCallback? onSessionExpired;

  late final ApiService api = ApiService(this);

  static const _tokenKey = "auth_token";
  static const _uidKey = "auth_uid";
  static const _emailKey = "auth_email";

  /// A valid bearer token for API calls. Firebase tokens refresh themselves when near expiry.
  Future<String?> token() async {
    if (kUseFirebase) {
      return FirebaseAuth.instance.currentUser?.getIdToken();
    }
    return _token;
  }

  Future<void> restore() async {
    if (kUseFirebase) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        current = AuthUser(uid: user.uid, email: user.email ?? "");
        notifyListeners();
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final uid = prefs.getString(_uidKey);
    final email = prefs.getString(_emailKey);
    if (token != null && uid != null && email != null) {
      _token = token;
      current = AuthUser(uid: uid, email: email);
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    _check(email, password);
    if (kUseFirebase) {
      try {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        _setFirebaseUser(cred.user!, email);
      } on FirebaseAuthException catch (e) {
        throw AuthException(_firebaseMessage(e));
      }
      return;
    }
    await _storeSession(await api.login(email.trim().toLowerCase(), password));
  }

  Future<void> register(String email, String password) async {
    _check(email, password);
    if (kUseFirebase) {
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        _setFirebaseUser(cred.user!, email);
      } on FirebaseAuthException catch (e) {
        throw AuthException(_firebaseMessage(e));
      }
      return;
    }
    await _storeSession(await api.register(email.trim().toLowerCase(), password));
  }

  Future<void> signOut() async {
    if (kUseFirebase) {
      await FirebaseAuth.instance.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_uidKey);
    await prefs.remove(_emailKey);
    _token = null;
    current = null;
    notifyListeners();
  }

  Future<void> sessionExpired() async {
    if (current == null) return;
    await signOut();
    onSessionExpired?.call();
  }

  void _check(String email, String password) {
    final problem = validateEmail(email) ?? validatePassword(password);
    if (problem != null) throw AuthException(problem);
  }

  void _setFirebaseUser(User user, String email) {
    current = AuthUser(uid: user.uid, email: user.email ?? email.trim());
    notifyListeners();
  }

  Future<void> _storeSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_uidKey, session.uid);
    await prefs.setString(_emailKey, session.email);
    _token = session.token;
    current = AuthUser(uid: session.uid, email: session.email);
    notifyListeners();
  }

  static String _firebaseMessage(FirebaseAuthException e) {
    switch (e.code) {
      case "user-not-found":
        return "No account found for this email. Register first.";
      case "wrong-password":
      case "invalid-credential":
        return "Wrong email or password.";
      case "email-already-in-use":
        return "An account with this email already exists. Sign in instead.";
      case "weak-password":
        return "Password must be at least 6 characters.";
      default:
        return e.message ?? "Sign-in failed.";
    }
  }

  static final _emailPattern = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

  static String? validateEmail(String email) {
    final value = email.trim();
    if (value.isEmpty) return "Enter your email.";
    if (!_emailPattern.hasMatch(value)) return "Enter a valid email address.";
    return null;
  }

  static String? validatePassword(String password) {
    if (password.isEmpty) return "Enter your password.";
    if (password.length < 6) return "Password must be at least 6 characters.";
    return null;
  }
}
