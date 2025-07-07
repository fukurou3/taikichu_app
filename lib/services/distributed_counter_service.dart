import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// 分散カウンター（Sharded Counter）サービス
/// 
/// 人気カウントダウンへの大量のいいね・参加が集中した際の
/// Firestore書き込み上限（毎秒1回）問題を解決する
/// 
/// 原理：
/// 1つのカウンターを複数のシャード（分割）に分散
/// 読み取り時は全シャードの合計値を計算
/// 書き込み時はランダムなシャードに分散して書き込み
class DistributedCounterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// シャード数（調整可能）
  /// 多いほど分散効果が高いが、読み取り時のコストが増加
  static const int _numShards = 10;
  
  /// ランダム生成器
  static final Random _random = Random();

  /// 分散カウンターのインクリメント
  /// 
  /// [countdownId] 対象カウントダウンのID
  /// [counterType] カウンタータイプ ('likes', 'comments', 'participants')
  /// [increment] 増加量（通常は1、減少時は-1）
  static Future<void> incrementCounter({
    required String countdownId,
    required String counterType,
    int increment = 1,
  }) async {
    try {
      // ランダムなシャードを選択
      final shardIndex = _random.nextInt(_numShards);
      final shardId = '${countdownId}_${counterType}_$shardIndex';
      
      // シャードへの書き込み
      final shardRef = _firestore
          .collection('distributed_counters')
          .doc(shardId);
      
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(shardRef);
        
        if (snapshot.exists) {
          final currentValue = (snapshot.data()?['count'] as int?) ?? 0;
          transaction.update(shardRef, {
            'count': currentValue + increment,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          // シャードが存在しない場合は新規作成
          transaction.set(shardRef, {
            'countdownId': countdownId,
            'counterType': counterType,
            'shardIndex': shardIndex,
            'count': increment,
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      });
      
      print('DistributedCounterService - Incremented $counterType for $countdownId (shard $shardIndex): +$increment');
      
    } catch (e) {
      print('DistributedCounterService - Error incrementing counter: $e');
      // エラーでもアプリを停止させない
    }
  }

  /// 分散カウンターの合計値を取得
  /// 
  /// [countdownId] 対象カウントダウンのID
  /// [counterType] カウンタータイプ ('likes', 'comments', 'participants')
  /// 戻り値: 全シャードの合計値
  static Future<int> getCounterValue({
    required String countdownId,
    required String counterType,
  }) async {
    try {
      // 全シャードを並列で読み取り
      final List<Future<DocumentSnapshot>> shardFutures = [];
      
      for (int i = 0; i < _numShards; i++) {
        final shardId = '${countdownId}_${counterType}_$i';
        final shardRef = _firestore
            .collection('distributed_counters')
            .doc(shardId);
        shardFutures.add(shardRef.get());
      }
      
      final shardSnapshots = await Future.wait(shardFutures);
      
      // 全シャードの値を合計
      int totalCount = 0;
      for (final snapshot in shardSnapshots) {
        if (snapshot.exists) {
          final count = (snapshot.data() as Map<String, dynamic>?)?['count'] as int? ?? 0;
          totalCount += count;
        }
      }
      
      return totalCount;
      
    } catch (e) {
      print('DistributedCounterService - Error getting counter value: $e');
      return 0; // エラー時は0を返す
    }
  }

  /// 分散カウンターの値をリアルタイムで監視
  /// 
  /// [countdownId] 対象カウントダウンのID
  /// [counterType] カウンタータイプ ('likes', 'comments', 'participants')
  /// 戻り値: カウンター値のStream
  static Stream<int> getCounterStream({
    required String countdownId,
    required String counterType,
  }) {
    // 全シャードの変更を監視
    final List<Stream<DocumentSnapshot>> shardStreams = [];
    
    for (int i = 0; i < _numShards; i++) {
      final shardId = '${countdownId}_${counterType}_$i';
      final shardRef = _firestore
          .collection('distributed_counters')
          .doc(shardId);
      shardStreams.add(shardRef.snapshots());
    }
    
    // 複数のStreamを結合し、合計値を計算
    return _combineShardStreams(shardStreams);
  }

  /// 複数のシャードストリームを結合して合計値を計算
  static Stream<int> _combineShardStreams(List<Stream<DocumentSnapshot>> shardStreams) {
    return Stream.periodic(const Duration(seconds: 1), (count) => count)
        .asyncMap((_) async {
          try {
            int totalCount = 0;
            
            for (final stream in shardStreams) {
              // 各ストリームの最新値を取得
              await for (final snapshot in stream.take(1)) {
                if (snapshot.exists) {
                  final count = (snapshot.data() as Map<String, dynamic>?)?['count'] as int? ?? 0;
                  totalCount += count;
                }
              }
            }
            
            return totalCount;
          } catch (e) {
            print('DistributedCounterService - Error in stream combination: $e');
            return 0;
          }
        })
        .distinct(); // 重複する値をフィルタ
  }

  /// メンテナンス用：古いシャードデータのクリーンアップ
  /// 
  /// 定期的に実行してストレージコストを抑制
  static Future<void> cleanupOldShards({int daysToKeep = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      const batchSize = 100;
      
      print('DistributedCounterService - Starting cleanup of shards older than $daysToKeep days...');
      
      while (true) {
        final query = _firestore
            .collection('distributed_counters')
            .where('lastUpdated', isLessThan: Timestamp.fromDate(cutoffDate))
            .limit(batchSize);
            
        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) break;
        
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        
        await batch.commit();
        print('DistributedCounterService - Deleted ${snapshot.docs.length} old shards');
      }
      
      print('DistributedCounterService - Cleanup completed');
      
    } catch (e) {
      print('DistributedCounterService - Error during cleanup: $e');
    }
  }

  /// 既存のカウンターから分散カウンターへのマイグレーション
  /// 
  /// 既存のcountsコレクションのカウンター値を
  /// 分散カウンターシステムに移行する際に使用
  static Future<void> migrateExistingCounters() async {
    try {
      print('DistributedCounterService - Starting migration of existing counters...');
      
      const batchSize = 50;
      var lastDoc;
      var processedCount = 0;

      while (true) {
        Query query = _firestore.collection('counts').limit(batchSize);
        
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) break;

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final countdownId = doc.id;
          
          // 各カウンタータイプを移行
          final counters = {
            'likes': data['likesCount'] as int? ?? 0,
            'comments': data['commentsCount'] as int? ?? 0,
            'participants': data['participantsCount'] as int? ?? 0,
          };
          
          for (final entry in counters.entries) {
            if (entry.value > 0) {
              // 初期値を最初のシャードに設定
              final shardId = '${countdownId}_${entry.key}_0';
              await _firestore
                  .collection('distributed_counters')
                  .doc(shardId)
                  .set({
                'countdownId': countdownId,
                'counterType': entry.key,
                'shardIndex': 0,
                'count': entry.value,
                'createdAt': FieldValue.serverTimestamp(),
                'lastUpdated': FieldValue.serverTimestamp(),
                'migrated': true,
              });
            }
          }
        }

        processedCount += snapshot.docs.length;
        lastDoc = snapshot.docs.last;
        
        print('DistributedCounterService - Migrated $processedCount documents...');
      }
      
      print('DistributedCounterService - Migration completed. Total processed: $processedCount');
      
    } catch (e) {
      print('DistributedCounterService - Error during migration: $e');
    }
  }
}