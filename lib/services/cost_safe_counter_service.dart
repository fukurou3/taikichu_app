import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// コスト安全な分散カウンターサービス
/// 
/// 🎯 目的: 分散カウンターの読み取りコスト爆発を防ぐ
/// 
class CostSafeCounterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _numShards = 10;
  static final Random _random = Random();

  /// 【安全】分散カウンターのインクリメント
  /// 
  /// 書き込みは分散して行い、ホットスポット問題を回避
  static Future<void> incrementCounter({
    required String countdownId,
    required String counterType,
    int increment = 1,
  }) async {
    try {
      // ランダムなシャードを選択
      final shardIndex = _random.nextInt(_numShards);
      final shardId = '${countdownId}_${counterType}_$shardIndex';
      
      // シャードへの書き込み（コスト安全）
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
            // 集計フラグ（Cloud Functionsが参照）
            'needsAggregation': true,
          });
        } else {
          transaction.set(shardRef, {
            'countdownId': countdownId,
            'counterType': counterType,
            'shardIndex': shardIndex,
            'count': increment,
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'needsAggregation': true,
          });
        }
      });
      
      print('CostSafeCounterService - Incremented $counterType for $countdownId (shard $shardIndex): +$increment');
      
    } catch (e) {
      print('CostSafeCounterService - Error incrementing counter: $e');
    }
  }

  /// 【安全・高速】集計済みカウンター値を取得
  /// 
  /// 🎯 10シャードを毎回読み取る代わりに、
  /// 事前集計された counts ドキュメントから1回で取得
  static Future<int> getCounterValue({
    required String countdownId,
    required String counterType,
  }) async {
    try {
      // counts ドキュメントから集計済み値を取得（1回の読み取りのみ）
      final countdownRef = _firestore.collection('counts').doc(countdownId);
      final snapshot = await countdownRef.get();
      
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        return data['${counterType}Count'] as int? ?? 0;
      }
      
      return 0;
    } catch (e) {
      print('CostSafeCounterService - Error getting counter value: $e');
      return 0;
    }
  }

  /// 【緊急フォールバック】シャード直接読み取り
  /// 
  /// ⚠️ 集計が遅れている場合のみ使用
  /// ⚠️ コストが高いため多用禁止
  static Future<int> getCounterValueDirect({
    required String countdownId,
    required String counterType,
  }) async {
    try {
      print('⚠️ CostSafeCounterService - Using EXPENSIVE direct shard reading for $counterType:$countdownId');
      
      // 10シャードを並列読み取り（高コスト！）
      final List<Future<DocumentSnapshot>> shardFutures = [];
      
      for (int i = 0; i < _numShards; i++) {
        final shardId = '${countdownId}_${counterType}_$i';
        final shardRef = _firestore
            .collection('distributed_counters')
            .doc(shardId);
        shardFutures.add(shardRef.get());
      }
      
      final shardSnapshots = await Future.wait(shardFutures);
      
      int totalCount = 0;
      for (final snapshot in shardSnapshots) {
        if (snapshot.exists) {
          final count = (snapshot.data() as Map<String, dynamic>?)?['count'] as int? ?? 0;
          totalCount += count;
        }
      }
      
      return totalCount;
      
    } catch (e) {
      print('CostSafeCounterService - Error in direct counter reading: $e');
      return 0;
    }
  }

  /// 【Cloud Functions用】シャード集計処理
  /// 
  /// 🎯 数分おきに実行して、シャード値を counts ドキュメントに集約
  /// 📊 この処理により、クライアントの読み取りコストを90%削減
  static Future<void> aggregateShards({
    String? specificCountdownId,
    int batchSize = 50,
  }) async {
    try {
      print('CostSafeCounterService - Starting shard aggregation...');
      
      // 集計が必要なシャードを検索
      Query query = _firestore
          .collection('distributed_counters')
          .where('needsAggregation', isEqualTo: true)
          .limit(batchSize);
      
      if (specificCountdownId != null) {
        query = query.where('countdownId', isEqualTo: specificCountdownId);
      }
      
      final shardsSnapshot = await query.get();
      if (shardsSnapshot.docs.isEmpty) {
        print('CostSafeCounterService - No shards need aggregation');
        return;
      }
      
      // カウントダウンID別にシャードをグループ化
      final Map<String, Map<String, List<QueryDocumentSnapshot>>> groupedShards = {};
      
      for (final doc in shardsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final countdownId = data['countdownId'] as String;
        final counterType = data['counterType'] as String;
        
        groupedShards.putIfAbsent(countdownId, () => {});
        groupedShards[countdownId]!.putIfAbsent(counterType, () => []);
        groupedShards[countdownId]![counterType]!.add(doc);
      }
      
      // 各カウントダウンのカウンターを集計
      for (final countdownEntry in groupedShards.entries) {
        final countdownId = countdownEntry.key;
        final counterTypes = countdownEntry.value;
        
        await _aggregateCountdownCounters(countdownId, counterTypes);
      }
      
      print('CostSafeCounterService - Aggregation completed for ${groupedShards.length} countdowns');
      
    } catch (e) {
      print('CostSafeCounterService - Error during aggregation: $e');
    }
  }

  /// 特定カウントダウンのカウンター集計
  static Future<void> _aggregateCountdownCounters(
    String countdownId,
    Map<String, List<QueryDocumentSnapshot>> counterTypes,
  ) async {
    try {
      final countdownRef = _firestore.collection('counts').doc(countdownId);
      
      await _firestore.runTransaction((transaction) async {
        final countdownSnapshot = await transaction.get(countdownRef);
        
        if (!countdownSnapshot.exists) {
          print('CostSafeCounterService - Countdown $countdownId not found, skipping aggregation');
          return;
        }
        
        final currentData = countdownSnapshot.data() as Map<String, dynamic>;
        final updatedData = <String, dynamic>{};
        final shardsToUpdate = <DocumentReference>[];
        
        // 各カウンタータイプを集計
        for (final counterEntry in counterTypes.entries) {
          final counterType = counterEntry.key;
          final shards = counterEntry.value;
          
          int totalCount = 0;
          for (final shard in shards) {
            final shardData = shard.data() as Map<String, dynamic>;
            totalCount += (shardData['count'] as int?) ?? 0;
            shardsToUpdate.add(shard.reference);
          }
          
          // counts ドキュメントを更新
          updatedData['${counterType}Count'] = totalCount;
        }
        
        if (updatedData.isNotEmpty) {
          updatedData['lastAggregatedAt'] = FieldValue.serverTimestamp();
          transaction.update(countdownRef, updatedData);
          
          // シャードの集計フラグをリセット
          for (final shardRef in shardsToUpdate) {
            transaction.update(shardRef, {
              'needsAggregation': false,
              'lastAggregatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      });
      
      print('CostSafeCounterService - Aggregated counters for $countdownId');
      
    } catch (e) {
      print('CostSafeCounterService - Error aggregating countdown $countdownId: $e');
    }
  }

  /// システム監視: 集計の遅延を検出
  static Future<Map<String, dynamic>> getAggregationHealth() async {
    try {
      // 集計待ちシャード数を取得
      final pendingSnapshot = await _firestore
          .collection('distributed_counters')
          .where('needsAggregation', isEqualTo: true)
          .count()
          .get();
      
      final pendingCount = pendingSnapshot.count;
      
      // 最新の集計時刻を取得
      final recentSnapshot = await _firestore
          .collection('counts')
          .where('lastAggregatedAt', isGreaterThan: 
            Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 10))))
          .count()
          .get();
      
      final recentAggregations = recentSnapshot.count;
      
      return {
        'pendingShards': pendingCount,
        'recentAggregations': recentAggregations,
        'status': pendingCount > 1000 ? 'warning' : 'healthy',
        'recommendation': pendingCount > 1000 
            ? 'Increase aggregation frequency'
            : 'Normal operation',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}