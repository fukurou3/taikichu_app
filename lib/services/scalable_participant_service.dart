import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cost_safe_counter_service.dart';
import 'scalable_trend_service.dart';

/// スケーラブルな参加者サービス
/// 
/// 分散カウンターとイベント駆動型トレンド更新に対応
/// 大量の参加が集中してもFirestore書き込み上限に引っかからない
class ScalableParticipantService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// カウントダウンへの参加/参加解除（分散カウンター対応）
  static Future<bool> toggleParticipation(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    try {
      // 参加状態を確認・更新
      final participantRef = _firestore
          .collection('participants')
          .doc('${countdownId}_${user.uid}');

      return await _firestore.runTransaction((transaction) async {
        final participantSnapshot = await transaction.get(participantRef);
        final isCurrentlyParticipating = participantSnapshot.exists;
        
        if (isCurrentlyParticipating) {
          // 参加解除
          transaction.delete(participantRef);
          
          // 【安全】分散カウンターをデクリメント
          await CostSafeCounterService.incrementCounter(
            countdownId: countdownId,
            counterType: 'participants',
            increment: -1,
          );
          
          // トレンドスコア更新
          await ScalableTrendService.updateTrendScoreOnAction(
            countdownId: countdownId,
            actionType: 'participate',
            increment: -1,
          );
          
          return false;
        } else {
          // 参加追加
          transaction.set(participantRef, {
            'countdownId': countdownId,
            'userId': user.uid,
            'participatedAt': FieldValue.serverTimestamp(),
          });
          
          // 【安全】分散カウンターをインクリメント
          await CostSafeCounterService.incrementCounter(
            countdownId: countdownId,
            counterType: 'participants',
            increment: 1,
          );
          
          // トレンドスコア更新
          await ScalableTrendService.updateTrendScoreOnAction(
            countdownId: countdownId,
            actionType: 'participate',
            increment: 1,
          );
          
          return true;
        }
      });
      
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
      final doc = await _firestore
          .collection('participants')
          .doc('${countdownId}_${user.uid}')
          .get();
      return doc.exists;
    } catch (e) {
      print('ScalableParticipantService - Error checking participation: $e');
      return false;
    }
  }

  /// 【安全・高速】集計済み参加者数を取得
  /// 
  /// 🎯 10シャードを毎回読み取る代わりに、集計済み値を1回で取得
  /// 💰 コストを90%削減
  static Future<int> getParticipantsCount(String countdownId) async {
    return await CostSafeCounterService.getCounterValue(
      countdownId: countdownId,
      counterType: 'participants',
    );
  }

  /// 【緊急時のみ】シャード直接読み取り
  /// 
  /// ⚠️ 集計が遅れている場合の最後の手段
  /// ⚠️ 高コストのため多用禁止
  static Future<int> getParticipantsCountDirect(String countdownId) async {
    return await CostSafeCounterService.getCounterValueDirect(
      countdownId: countdownId,
      counterType: 'participants',
    );
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