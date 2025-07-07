# 真にスケーラブルなリアルタイム分析基盤

## アーキテクチャ概要

```
[Flutter App] → [Cloud Functions] → [Pub/Sub] → [Dataflow] → [Memorystore Redis]
                      ↓                                           ↑
                [Firestore]                              [Client Reading]
```

## Cloud Functions 実装例

### 1. publishAnalyticsEvent (HTTP Trigger)

```javascript
const functions = require('firebase-functions');
const {PubSub} = require('@google-cloud/pubsub');
const pubsub = new PubSub();

exports.publishAnalyticsEvent = functions.https.onRequest(async (req, res) => {
  try {
    const eventData = req.body;
    
    // イベントデータを Pub/Sub に送信
    const messageId = await pubsub
      .topic('analytics-events')
      .publishMessage({
        data: Buffer.from(JSON.stringify(eventData)),
        attributes: {
          eventType: eventData.eventType,
          countdownId: eventData.countdownId,
          timestamp: eventData.timestamp,
        },
      });

    res.json({ success: true, messageId });
  } catch (error) {
    console.error('Error publishing event:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 2. getTrendScore (HTTP Trigger)

```javascript
const {Memorystore} = require('@google-cloud/memorystore');
const redis = require('redis');

const redisClient = redis.createClient({
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT,
});

exports.getTrendScore = functions.https.onRequest(async (req, res) => {
  try {
    const countdownId = req.query.countdownId;
    
    // Redis から高速取得
    const trendScore = await redisClient.get(`trend_score:${countdownId}`);
    
    res.json({ 
      trendScore: parseFloat(trendScore || '0'),
      cached: true,
      timestamp: Date.now(),
    });
  } catch (error) {
    console.error('Error getting trend score:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 3. getSystemHealth (システム監視)

```javascript
exports.getSystemHealth = functions.https.onRequest(async (req, res) => {
  try {
    // Pub/Sub の未処理メッセージ数を取得
    const subscription = pubsub.subscription('analytics-events-subscription');
    const [metadata] = await subscription.getMetadata();
    
    // Dataflow ジョブの状態を取得
    const dataflowStatus = await getDataflowJobStatus();
    
    // Redis の接続状態確認
    const redisHealth = await checkRedisHealth();
    
    const health = {
      status: 'healthy',
      pubsub: {
        pendingMessages: metadata.numOutstandingMessages || 0,
        ackDeadlineSeconds: metadata.ackDeadlineSeconds,
      },
      dataflow: dataflowStatus,
      redis: redisHealth,
      lastUpdated: new Date().toISOString(),
    };
    
    // アラート閾値チェック
    if (health.pubsub.pendingMessages > 10000) {
      health.status = 'warning';
      health.alerts = ['High pending message count'];
    }
    
    res.json(health);
  } catch (error) {
    res.status(500).json({ 
      status: 'error', 
      error: error.message 
    });
  }
});
```

## Dataflow パイプライン設計

### Apache Beam パイプライン (Java)

```java
public class RealtimeAnalyticsPipeline {
    public static void main(String[] args) {
        DataflowPipelineOptions options = PipelineOptionsFactory.as(DataflowPipelineOptions.class);
        Pipeline pipeline = Pipeline.create(options);
        
        pipeline
            // 1. Pub/Sub からイベントストリームを読み取り
            .apply("Read Events", 
                PubsubIO.readMessages().fromTopic(options.getInputTopic()))
            
            // 2. JSON パース
            .apply("Parse Events", 
                ParDo.of(new ParseEventFn()))
            
            // 3. 時間ウィンドウで集計（1分間）
            .apply("Window Events", 
                Window.<AnalyticsEvent>into(
                    FixedWindows.of(Duration.standardMinutes(1)))
                    .triggering(AfterWatermark.pastEndOfWindow()
                        .withEarlyFirings(AfterProcessingTime
                            .pastFirstElementInPane()
                            .plusDelayOf(Duration.standardSeconds(10))))
                    .withAllowedLateness(Duration.standardMinutes(5))
                    .accumulatingFiredPanes())
            
            // 4. カウントダウンIDでグループ化して集計
            .apply("Group by Countdown", 
                GroupByKey.<String, AnalyticsEvent>create())
            
            // 5. トレンドスコア計算
            .apply("Calculate Trend Scores", 
                ParDo.of(new CalculateTrendScoreFn()))
            
            // 6. Redis に結果を書き込み
            .apply("Write to Redis", 
                ParDo.of(new WriteToRedisFn()));
        
        pipeline.run().waitUntilFinish();
    }
}

// トレンドスコア計算クラス
public static class CalculateTrendScoreFn extends DoFn<KV<String, Iterable<AnalyticsEvent>>, TrendScoreResult> {
    @ProcessElement
    public void processElement(ProcessContext c) {
        String countdownId = c.element().getKey();
        Iterable<AnalyticsEvent> events = c.element().getValue();
        
        double trendScore = 0.0;
        int likeCount = 0;
        int commentCount = 0;
        int participationCount = 0;
        int viewCount = 0;
        
        // イベントタイプ別に集計
        for (AnalyticsEvent event : events) {
            switch (event.getEventType()) {
                case "like_added":
                    likeCount++;
                    trendScore += 3.0; // いいねの重み
                    break;
                case "like_removed":
                    likeCount--;
                    trendScore -= 3.0;
                    break;
                case "comment_created":
                    commentCount++;
                    trendScore += 5.0; // コメントの重み
                    break;
                case "participation_added":
                    participationCount++;
                    trendScore += 10.0; // 参加の重み
                    break;
                case "participation_removed":
                    participationCount--;
                    trendScore -= 10.0;
                    break;
                case "view":
                    viewCount++;
                    trendScore += 1.0; // 閲覧の重み
                    break;
            }
        }
        
        // 結果を出力
        TrendScoreResult result = TrendScoreResult.newBuilder()
            .setCountdownId(countdownId)
            .setTrendScore(trendScore)
            .setLikeCount(likeCount)
            .setCommentCount(commentCount)
            .setParticipationCount(participationCount)
            .setViewCount(viewCount)
            .setTimestamp(System.currentTimeMillis())
            .build();
            
        c.output(result);
    }
}
```

## Redis データ構造設計

### キー設計

```
// トレンドスコア
trend_score:{countdownId} → double

// 分散カウンター集計値
counter:likes:{countdownId} → int
counter:comments:{countdownId} → int
counter:participants:{countdownId} → int
counter:views:{countdownId} → int

// ランキング (Sorted Set)
ranking:global → ZSET (score: trendScore, member: countdownId)
ranking:category:{category} → ZSET

// 時系列データ (1時間ごと)
timeseries:likes:{countdownId}:{hour} → int
timeseries:views:{countdownId}:{hour} → int
```

### TTL 設定

```redis
# トレンドスコアは24時間で期限切れ
EXPIRE trend_score:countdown123 86400

# カウンターは永続化
PERSIST counter:likes:countdown123

# 時系列データは7日で期限切れ  
EXPIRE timeseries:views:countdown123:2024010112 604800
```

## 性能予測

### データ量別の性能比較

| ユーザー数 | イベント/秒 | 従来コスト/月 | 新アーキテクチャコスト/月 | レスポンス時間 |
|-----------|-------------|---------------|---------------------------|----------------|
| 1,000 | 100 | $50 | $30 | 50ms → 5ms |
| 10,000 | 1,000 | $500 | $100 | 100ms → 5ms |
| 100,000 | 10,000 | $5,000 | $300 | 500ms → 10ms |
| 1,000,000 | 100,000 | $50,000 | $1,000 | 2000ms → 15ms |

### スケーラビリティ指標

- **Pub/Sub**: 100万メッセージ/秒 対応
- **Dataflow**: 自動スケーリング (1〜1000ワーカー)
- **Memorystore**: 300GB、毎秒100万オペレーション
- **可用性**: 99.95% (マルチリージョン構成時は99.99%)

## 移行戦略

### フェーズ1: 並行運用 (1週間)
- 既存システムと新システムを並行稼働
- データ整合性を確認

### フェーズ2: 段階的切り替え (1週間)  
- 読み取りを徐々に新システムに移行
- 書き込みは両システムに送信

### フェーズ3: 完全移行 (1週間)
- 全トラフィックを新システムに移行
- 旧システムを段階的に停止

### フェーズ4: 最適化 (継続)
- パフォーマンス監視と調整
- コスト最適化