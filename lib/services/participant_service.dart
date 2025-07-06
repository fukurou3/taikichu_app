import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParticipantService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ユーザーがカウントダウンに参加する
  static Future<bool> participateInCountdown(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    final participantRef = _firestore
        .collection('countdownParticipants')
        .doc('${countdownId}_${user.uid}');

    try {
      // 既に参加しているかチェック
      final doc = await participantRef.get();
      if (doc.exists) {
        // 参加を取り消す
        await participantRef.delete();
        
        // カウントダウンの参加者数を減らす
        await _firestore.collection('counts').doc(countdownId).update({
          'participantsCount': FieldValue.increment(-1),
        });
        
        return false; // 参加解除
      } else {
        // 参加する
        await participantRef.set({
          'countdownId': countdownId,
          'userId': user.uid,
          'participatedAt': FieldValue.serverTimestamp(),
        });
        
        // カウントダウンの参加者数を増やす
        await _firestore.collection('counts').doc(countdownId).update({
          'participantsCount': FieldValue.increment(1),
        });
        
        return true; // 参加
      }
    } catch (e) {
      throw Exception('参加処理に失敗しました: $e');
    }
  }

  /// ユーザーがカウントダウンに参加しているかチェック
  static Future<bool> isParticipating(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await _firestore
        .collection('countdownParticipants')
        .doc('${countdownId}_${user.uid}')
        .get();
    
    return doc.exists;
  }

  /// ユーザーが参加しているカウントダウンIDのリストを取得
  static Future<List<String>> getUserParticipatedCountdowns() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return [];
    }

    try {
      final querySnapshot = await _firestore
          .collection('countdownParticipants')
          .where('userId', isEqualTo: user.uid)
          .get()
          .timeout(const Duration(seconds: 5)); // タイムアウト設定

      final ids = querySnapshot.docs
          .map((doc) {
            final data = doc.data();
            return data['countdownId'] as String? ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toList();
      
      return ids;
    } catch (e) {
      // Firestoreエラー（権限、ネットワークエラーなど）の場合は空リストを返す
      print('ParticipantService - Safe fallback for error: $e');
      return [];
    }
  }

  /// ユーザーが参加しているカウントダウンのストリーム
  static Stream<List<String>> getUserParticipatedCountdownsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('countdownParticipants')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc.data()['countdownId'] as String)
            .toList());
  }
}