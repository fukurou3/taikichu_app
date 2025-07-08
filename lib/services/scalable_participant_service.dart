import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 参加者サービス (Phase0 - Firestore only)
/// 
/// Firestoreを直接使用し、マイクロサービス依存を排除
class ScalableParticipantService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// カウントダウンへの参加/参加解除
  static Future<bool> toggleParticipation(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    try {
      final isCurrentlyParticipating = await isParticipating(countdownId);
      
      if (isCurrentlyParticipating) {
        await _removeParticipation(countdownId, user.uid);
      } else {
        await _addParticipation(countdownId, user.uid);
      }
      
      return !isCurrentlyParticipating;
      
    } catch (e) {
      print('ScalableParticipantService - Error toggling participation: $e');
      throw Exception('参加処理に失敗しました: $e');
    }
  }

  /// 参加状態の確認
  static Future<bool> isParticipating(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('participants').doc('${user.uid}_$countdownId').get();
      return doc.exists;
    } catch (e) {
      print('ScalableParticipantService - Error checking participation: $e');
      return false;
    }
  }

  /// 参加者数を取得
  static Future<int> getParticipantsCount(String countdownId) async {
    try {
      final postDoc = await _firestore.collection('posts').doc(countdownId).get();
      if (postDoc.exists) {
        return postDoc.data()?['participantsCount'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('ScalableParticipantService - Error getting participants count: $e');
      return 0;
    }
  }

  /// 参加を追加
  static Future<void> _addParticipation(String countdownId, String userId) async {
    final batch = _firestore.batch();
    
    // 参加記録作成
    final participantRef = _firestore.collection('participants').doc('${userId}_$countdownId');
    batch.set(participantRef, {
      'userId': userId,
      'countdownId': countdownId,
      'participatedAt': FieldValue.serverTimestamp(),
    });
    
    // 投稿の参加者数更新
    final postRef = _firestore.collection('posts').doc(countdownId);
    batch.update(postRef, {'participantsCount': FieldValue.increment(1)});
    
    await batch.commit();
  }

  /// 参加を削除
  static Future<void> _removeParticipation(String countdownId, String userId) async {
    final batch = _firestore.batch();
    
    // 参加記録削除
    final participantRef = _firestore.collection('participants').doc('${userId}_$countdownId');
    batch.delete(participantRef);
    
    // 投稿の参加者数更新
    final postRef = _firestore.collection('posts').doc(countdownId);
    batch.update(postRef, {'participantsCount': FieldValue.increment(-1)});
    
    await batch.commit();
  }


  /// ユーザーが参加しているカウントダウンIDリストを取得
  static Future<List<String>> getUserParticipatedCountdowns() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('participants')
          .where('userId', isEqualTo: user.uid)
          .get()
          .timeout(const Duration(seconds: 10)); // タイムアウト設定

      final ids = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return data['countdownId'] as String? ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toList();
      
      return ids;
    } catch (e) {
      print('ScalableParticipantService - Error getting user participations: $e');
      return []; // エラー時は空リストを返す
    }
  }

  /// 特定カウントダウンの参加者一覧
  static Future<List<Map<String, dynamic>>> getCountdownParticipants(
    String countdownId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('participants')
          .where('countdownId', isEqualTo: countdownId)
          .orderBy('participatedAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => {
                'userId': doc.data()['userId'],
                'participatedAt': doc.data()['participatedAt'],
              })
          .toList();
    } catch (e) {
      print('ScalableParticipantService - Error getting participants: $e');
      return [];
    }
  }

  /// ユーザーの参加カウントダウンをリアルタイム監視
  static Stream<List<String>> getUserParticipatedCountdownsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('participants')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc.data()['countdownId'] as String)
            .toList())
        .handleError((error) {
          print('ScalableParticipantService - Stream error: $error');
          return <String>[];
        });
  }
}