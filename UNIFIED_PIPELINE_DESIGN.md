# 統一パイプライン設計書

## 🎯 設計目標

現在の混在アーキテクチャを完全にPub/Sub中心の統一パイプラインに移行し、以下を実現：

- **データ整合性**: 全ての更新が単一パイプラインを通過
- **コスト最適化**: 重複処理の完全排除
- **スケーラビリティ**: 無限拡張可能な設計
- **保守性**: 単一責任原則の徹底

## 🏗️ 新統一アーキテクチャ

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Client    │───▶│  Firestore  │───▶│  Pub/Sub    │───▶│ Cloud Run   │───▶│   Redis     │
│   Action    │    │  Trigger    │    │   Events    │    │  Analytics  │    │   Cache     │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼                   ▼
   ユーザー操作        イベント検知         非同期配信        リアルタイム処理      高速レスポンス
   (いいね/コメント)    (軽量トリガー)      (確実な配信)      (集約・計算)        (1-5ms)
```

## 📋 Phase 1: 重複処理の完全排除

### 1.1 削除対象の関数

#### Firebase Functions (functions/src/index.ts)
```typescript
// 🚨 削除対象: 直接更新を行う関数群
- onCommentCreate
- onCommentDelete  
- onLikeCreate
- onLikeDelete
- onViewCreate
- onRecentViewCreate
- incrementDistributedCounter
- updateTrendRankings (スケジュール)
```

#### コスト安全Functions (cloud_functions_cost_safe.js)
```typescript
// 🚨 削除対象: 重複集約処理
- aggregateCounters (一部機能のみ保持)
- aggregateSpecificCountdown
```

### 1.2 保持する関数

#### MVP Analytics Functions (mvp_analytics_functions.js)
```typescript
// ✅ 保持: イベント発行のみ
- onLikeCreate/Delete → Pub/Sub発行
- onParticipationCreate/Delete → Pub/Sub発行  
- onCommentCreate → Pub/Sub発行
- publishViewEvent → Pub/Sub発行
- getPubSubHealth → ヘルスチェック
```

## 📊 Phase 2: 統一パイプライン構築

### 2.1 イベント型定義

```typescript
interface UnifiedEvent {
  eventId: string;
  type: 'like_added' | 'like_removed' | 'comment_added' | 'participation_added' | 'participation_removed' | 'view';
  countdownId: string;
  userId: string;
  timestamp: string;
  metadata: {
    source: 'firestore_trigger' | 'client_direct';
    session_id?: string;
    batch_id?: string;
  };
}
```

### 2.2 Cloud Run Analytics Service 拡張

```python
# analytics-service/handlers/unified_processor.py

class UnifiedEventProcessor:
    """統一イベント処理クラス"""
    
    def __init__(self, redis_client):
        self.redis = redis_client
        self.batch_operations = []
    
    async def process_event(self, event: UnifiedEvent):
        """統一イベント処理メイン"""
        
        # 1. 基本カウンター更新
        await self._update_counters(event)
        
        # 2. トレンドスコア計算
        await self._calculate_trend_score(event)
        
        # 3. ランキング更新
        await self._update_rankings(event)
        
        # 4. リアルタイム通知
        await self._trigger_notifications(event)
    
    async def _update_counters(self, event: UnifiedEvent):
        """カウンター統一更新"""
        counter_key = f"counter:{event.countdownId}:{event.type.split('_')[0]}"
        
        if event.type.endswith('_added'):
            await self.redis.incr(counter_key)
        elif event.type.endswith('_removed'):
            await self.redis.decr(counter_key)
    
    async def _calculate_trend_score(self, event: UnifiedEvent):
        """トレンドスコア統一計算"""
        weights = {
            'like': 3.0,
            'comment': 5.0, 
            'participation': 10.0,
            'view': 1.0
        }
        
        event_weight = weights.get(event.type.split('_')[0], 1.0)
        increment = event_weight if event.type.endswith('_added') else -event_weight
        
        trend_key = f"trend_score:{event.countdownId}"
        await self.redis.incrbyfloat(trend_key, increment)
        
        # 時間減衰処理
        await self._apply_time_decay(event.countdownId)
    
    async def _update_rankings(self, event: UnifiedEvent):
        """ランキング統一更新"""
        trend_score = await self.redis.get(f"trend_score:{event.countdownId}")
        
        if trend_score:
            await self.redis.zadd(
                "ranking:global", 
                {event.countdownId: float(trend_score)}
            )
```

### 2.3 バッチ処理の統一

```python
# analytics-service/batch/unified_batch.py

class UnifiedBatchProcessor:
    """統一バッチ処理クラス"""
    
    async def sync_to_firestore(self):
        """Redis → Firestore 同期"""
        
        # 1. カウンター同期
        await self._sync_counters()
        
        # 2. トレンドスコア同期  
        await self._sync_trend_scores()
        
        # 3. ランキング同期
        await self._sync_rankings()
    
    async def _sync_counters(self):
        """カウンター一括同期"""
        pattern = "counter:*"
        keys = await self.redis.keys(pattern)
        
        batch = []
        for key in keys:
            countdown_id, counter_type = self._parse_counter_key(key)
            value = await self.redis.get(key)
            
            batch.append({
                'countdown_id': countdown_id,
                'counter_type': counter_type,
                'value': int(value)
            })
        
        # Firestore一括更新
        await self._batch_update_firestore(batch)
```

## 🔄 Phase 3: クライアント側の統一

### 3.1 統一分析クライアント

```dart
// lib/services/unified_analytics_service.dart

class UnifiedAnalyticsService {
  static const String _cloudRunUrl = 'https://analytics-service-xxxx.run.app';
  
  /// 統一イベント送信
  static Future<void> sendEvent({
    required String type,
    required String countdownId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final event = {
        'eventId': _generateEventId(),
        'type': type,
        'countdownId': countdownId,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'source': 'client_direct',
          'session_id': _getSessionId(),
          ...?metadata,
        },
      };
      
      // Cloud Run直接送信（高速）
      await http.post(
        Uri.parse('$_cloudRunUrl/events'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(event),
      );
      
    } catch (e) {
      print('UnifiedAnalyticsService - Error: $e');
      // フォールバック: Pub/Sub経由送信
      await _sendViaPubSub(type, countdownId, metadata);
    }
  }
  
  /// いいね統一処理
  static Future<void> sendLikeEvent(String countdownId, bool isAdding) async {
    await sendEvent(
      type: isAdding ? 'like_added' : 'like_removed',
      countdownId: countdownId,
    );
  }
  
  /// コメント統一処理
  static Future<void> sendCommentEvent(String countdownId) async {
    await sendEvent(
      type: 'comment_added',
      countdownId: countdownId,
    );
  }
}
```

### 3.2 既存サービスの段階的移行

```dart
// lib/services/countdown_like_service.dart - 移行例

class CountdownLikeService {
  static Future<void> toggleLike(String countdownId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('未認証');
      
      final likeDoc = await _firestore
          .collection('likes')
          .where('countdownId', isEqualTo: countdownId)
          .where('userId', isEqualTo: user.uid)
          .get();
      
      if (likeDoc.docs.isEmpty) {
        // いいね追加
        await _firestore.collection('likes').add({
          'countdownId': countdownId,
          'userId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        // 🚀 統一イベント送信（新方式）
        await UnifiedAnalyticsService.sendLikeEvent(countdownId, true);
        
      } else {
        // いいね削除
        await likeDoc.docs.first.reference.delete();
        
        // 🚀 統一イベント送信（新方式）
        await UnifiedAnalyticsService.sendLikeEvent(countdownId, false);
      }
    } catch (e) {
      print('CountdownLikeService - Error: $e');
    }
  }
}
```

## 📈 Phase 4: パフォーマンス最適化

### 4.1 Cache-First戦略

```dart
// lib/services/optimized_data_service.dart

class OptimizedDataService {
  static Future<Map<String, dynamic>> getCountdownData(String countdownId) async {
    try {
      // 1. Redis から高速取得（1-5ms）
      final cacheData = await MVPAnalyticsClient.getAnalyticsData(countdownId);
      
      if (cacheData.isNotEmpty) {
        return cacheData;
      }
      
      // 2. フォールバック: Firestore から取得（50-200ms）
      final firestoreData = await _getFromFirestore(countdownId);
      
      // 3. Redis にキャッシュ
      await _cacheToRedis(countdownId, firestoreData);
      
      return firestoreData;
      
    } catch (e) {
      print('OptimizedDataService - Error: $e');
      return {};
    }
  }
}
```

### 4.2 バッチ処理最適化

```python
# analytics-service/optimizations/batch_optimizer.py

class BatchOptimizer:
    """バッチ処理最適化"""
    
    def __init__(self, redis_client, firestore_client):
        self.redis = redis_client
        self.firestore = firestore_client
        self.batch_size = 500  # Firestore制限
    
    async def optimized_sync(self):
        """最適化された同期処理"""
        
        # 1. 変更検知
        changed_keys = await self._detect_changes()
        
        # 2. バッチサイズで分割
        batches = self._chunk_operations(changed_keys, self.batch_size)
        
        # 3. 並列処理
        tasks = [self._process_batch(batch) for batch in batches]
        await asyncio.gather(*tasks)
        
        # 4. 成功ログ
        print(f"Synced {len(changed_keys)} items in {len(batches)} batches")
```

## 🛡️ Phase 5: 信頼性・監視

### 5.1 エラーハンドリング

```python
# analytics-service/reliability/error_handler.py

class UnifiedErrorHandler:
    """統一エラーハンドリング"""
    
    async def handle_processing_error(self, event, error):
        """処理エラーハンドリング"""
        
        # 1. エラーログ
        logger.error(f"Event processing failed: {event.eventId}", exc_info=error)
        
        # 2. リトライキューに追加
        await self.redis.lpush("retry_queue", json.dumps(event))
        
        # 3. アラート送信（重要エラーのみ）
        if self._is_critical_error(error):
            await self._send_alert(event, error)
    
    async def process_retry_queue(self):
        """リトライ処理"""
        while True:
            event_json = await self.redis.brpop("retry_queue", timeout=60)
            if event_json:
                await self._retry_event_processing(json.loads(event_json))
```

### 5.2 監視・アラート

```python
# analytics-service/monitoring/unified_monitor.py

class UnifiedMonitor:
    """統一監視システム"""
    
    def __init__(self):
        self.metrics = {}
    
    async def track_event_processing(self, event, processing_time):
        """イベント処理メトリクス"""
        
        # 1. 処理時間記録
        self.metrics[f"processing_time_{event.type}"] = processing_time
        
        # 2. スループット記録
        await self.redis.incr(f"throughput_{event.type}_{datetime.now().hour}")
        
        # 3. エラー率監視
        if processing_time > 1000:  # 1秒以上は異常
            await self._trigger_slow_processing_alert(event)
```

## 🚀 実装順序

### Week 1: 重複排除
1. 重複する Firebase Functions の無効化
2. MVP Analytics Functions のみ残存
3. 基本イベントフロー確認

### Week 2: 統一パイプライン
1. Cloud Run Analytics Service 拡張
2. 統一イベント処理実装
3. Redis 統合テスト

### Week 3: クライアント移行
1. UnifiedAnalyticsService 実装
2. 既存サービスの段階的移行
3. パフォーマンステスト

### Week 4: 最適化・監視
1. Cache-First戦略実装
2. 監視・アラートシステム
3. 本番環境デプロイ

## 📊 期待効果

### パフォーマンス
- **レスポンス時間**: 100-500ms → 1-5ms (100倍向上)
- **スループット**: 100 ops/sec → 10,000 ops/sec (100倍向上)
- **可用性**: 99.9% → 99.95% (向上)

### コスト
- **Firestore読み取り**: 90%削減
- **Cloud Functions実行時間**: 80%削減  
- **総コスト**: $50,000/月 → $5,000/月 (90%削減)

### 開発効率
- **デバッグ時間**: 70%削減
- **新機能開発速度**: 3倍向上
- **保守性**: 大幅向上

この統一パイプライン設計により、スケーラブルで費用効率的、かつ保守しやすいアーキテクチャを実現します。