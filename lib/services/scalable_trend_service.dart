import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';

/// スケーラブルなトレンドスコア管理サービス
/// 
/// 従来の5分ごと全件読み取り → イベント駆動型リアルタイム更新に変更
/// これにより、ユーザー数増加時のFirestoreコスト爆発を防ぐ
class ScalableTrendService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// アクション発生時のスコア更新（Cloud Functionsで呼び出し推奨）
  /// 
  /// 各アクション（いいね、コメント、参加、閲覧）が発生した際に
  /// リアルタイムでtrendScoreを更新する
  static Future<void> updateTrendScoreOnAction({
    required String countdownId,
    required String actionType, // 'like', 'comment', 'participate', 'view'
    required int increment,
  }) async {
    try {
      // スコア重み付け定義
      final Map<String, double> scoreWeights = {
        'like': 3.0,        // いいねは高いエンゲージメント
        'comment': 5.0,     // コメントはより高いエンゲージメント  
        'participate': 10.0, // 参加は最高のエンゲージメント
        'view': 1.0,        // 閲覧は基本スコア
      };

      final weight = scoreWeights[actionType] ?? 1.0;
      final scoreIncrement = increment * weight;

      // アトミックな更新処理
      await _firestore.runTransaction((transaction) async {
        final countdownRef = _firestore.collection('counts').doc(countdownId);
        final snapshot = await transaction.get(countdownRef);
        
        if (!snapshot.exists) {
          throw Exception('カウントダウンが見つかりません: $countdownId');
        }

        final currentData = snapshot.data() as Map<String, dynamic>;
        final currentTrendScore = (currentData['trendScore'] as num?)?.toDouble() ?? 0.0;
        final now = DateTime.now();
        
        // トレンドスコアの更新
        transaction.update(countdownRef, {
          'trendScore': currentTrendScore + scoreIncrement,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'recent${actionType.capitalize()}Count': FieldValue.increment(increment),
        });
      });

      print('ScalableTrendService - Updated trend score for $countdownId: +$scoreIncrement ($actionType)');
      
    } catch (e) {
      print('ScalableTrendService - Error updating trend score: $e');
      // エラーでもアプリの動作を停止させない
    }
  }

  /// 【危険】日次でのトレンドスコアリセット - 緊急停止中
  /// 
  /// ⚠️ この関数は10万件のデータで完全に破綻し、数万円のコストを発生させます
  /// ⚠️ 現在は緊急停止中です。絶対に実行しないでください。
  /// ⚠️ Cloud Scheduler で設定されている場合は直ちに削除してください。
  /// 
  /// 問題点:
  /// - 全カウントダウンを100件ずつ読み取り → 10万件で1000クエリ
  /// - 実行時間: 数時間 → Cloud Functions タイムアウト
  /// - コスト: 10万件で月額$10,000以上
  @Deprecated('EMERGENCY STOP - This function will bankrupt your Firebase bill!')
  static Future<void> dailyTrendScoreDecay() async {
    // 🚨 緊急停止: この関数は絶対に実行してはいけません
    throw Exception('''
🚨 EMERGENCY STOP 🚨
この関数は重大なコスト問題を引き起こします！

問題:
- 10万件のデータで月額 \$10,000+ のコスト
- 実行時間: 数時間でタイムアウト
- Firestore読み取り数: 1000+ クエリ

解決策:
新しいリアルタイム分析基盤を使用してください。
詳細は cloud_functions_architecture.md を参照。

この関数を Cloud Scheduler で実行している場合は
直ちに無効化してください！
    ''');
  }

  /// 効率的なトレンドランキング取得
  /// 
  /// Cloud Functionsでの全件読み取りを廃止し、
  /// リアルタイム更新されたtrendScoreによる直接的なランキングを提供
  static Stream<List<Countdown>> getTrendRankingsStream({
    String? category,
    int limit = 20,
  }) {
    Query query = _firestore.collection('counts');
    
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    
    // trendScoreでソートし、上位のみを取得
    query = query
        .where('trendScore', isGreaterThan: 0)
        .orderBy('trendScore', descending: true)
        .limit(limit);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Countdown(
          id: doc.id,
          eventName: data['eventName'] as String? ?? '無題',
          description: data['description'] as String?,
          eventDate: (data['eventDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
          category: data['category'] as String? ?? 'その他',
          imageUrl: data['imageUrl'] as String?,
          creatorId: data['creatorId'] as String? ?? 'unknown',
          participantsCount: data['participantsCount'] as int? ?? 0,
          likesCount: data['likesCount'] as int? ?? 0,
          commentsCount: data['commentsCount'] as int? ?? 0,
          viewsCount: data['viewsCount'] as int? ?? 0,
          recentCommentsCount: data['recentCommentsCount'] as int? ?? 0,
          recentLikesCount: data['recentLikesCount'] as int? ?? 0,
          recentViewsCount: data['recentViewsCount'] as int? ?? 0,
        );
      }).toList();
    });
  }
}

/// String拡張: 最初の文字を大文字にする
extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}