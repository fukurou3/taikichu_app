import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 現在のユーザーのストリーム
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 現在のユーザー
  static User? get currentUser => _auth.currentUser;

  // ログイン状態の確認
  static bool get isLoggedIn => _auth.currentUser != null;

  // ユーザー登録
  static Future<UserCredential?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestoreにユーザー情報を保存
      if (result.user != null) {
        await _firestore.collection('users').doc(result.user!.uid).set({
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return result;
    } catch (e) {
      print('ユーザー登録エラー: $e');
      rethrow;
    }
  }

  // ログイン
  static Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('ログインエラー: $e');
      rethrow;
    }
  }

  // ログアウト
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('ログアウトエラー: $e');
      rethrow;
    }
  }

  // ユーザー情報の取得
  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      print('ユーザー情報取得エラー: $e');
      return null;
    }
  }
}