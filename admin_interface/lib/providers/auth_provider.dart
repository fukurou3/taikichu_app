import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  String? _userRole;
  bool _isLoading = true;
  String? _errorMessage;

  User? get user => _user;
  String? get userRole => _userRole;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _userRole == 'moderator' || _userRole == 'superadmin';
  bool get isSuperAdmin => _userRole == 'superadmin';

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _user = user;
    _isLoading = true;
    notifyListeners();

    if (user != null) {
      await _updateUserRole();
    } else {
      _userRole = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _updateUserRole() async {
    try {
      final idTokenResult = await _user?.getIdTokenResult();
      _userRole = idTokenResult?.claims?['role'] as String?;
    } catch (e) {
      print('Error getting user role: $e');
      _userRole = null;
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        await _updateUserRole();
        
        if (!isAdmin) {
          await signOut();
          _errorMessage = 'アクセス権限がありません。管理者アカウントでログインしてください。';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _userRole = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> getIdToken() async {
    try {
      return await _user?.getIdToken();
    } catch (e) {
      print('Error getting ID token: $e');
      return null;
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'ユーザーが見つかりません。';
        case 'wrong-password':
          return 'パスワードが正しくありません。';
        case 'invalid-email':
          return 'メールアドレスの形式が正しくありません。';
        case 'user-disabled':
          return 'このアカウントは無効になっています。';
        case 'too-many-requests':
          return 'リクエストが多すぎます。しばらく待ってからお試しください。';
        default:
          return 'ログインに失敗しました: ${error.message}';
      }
    }
    return 'ログインに失敗しました。';
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}