# ファンアウト・アーキテクチャ実装計画

## 🎯 概要
現在の「読み取り時生成」から「書き込み時生成」のファンアウト・アーキテクチャに移行し、フォロワー数に関係なく一定のパフォーマンスを実現する。

## 🔍 現在の問題点
- **simple_home_screen.dart:141** - 全カウントダウンを取得後、クライアント側でフィルタリング
- **profile_screen.dart:166** - 全カウントダウンを取得後、参加済みIDでフィルタリング
- フォロワー数に比例してクライアント側処理が増加
- 全データを毎回取得してからフィルタリング

## 🏗️ 実装方針
既存の統一パイプライン・アーキテクチャを拡張してファンアウト機能を実装

### Phase 1: Redis フォロー管理 + API実装

#### 1.1 Redis データ構造拡張
```redis
# フォロー関係管理
user_follows:{user_id}              # Set: フォロー中のユーザーリスト
user_followers:{user_id}            # Set: フォロワーリスト
follow_count:{user_id}              # Hash: フォロー数・フォロワー数

# タイムライン管理
timeline:{user_id}                  # Sorted Set: パーソナルタイムライン
global_timeline                     # Sorted Set: グローバルタイムライン
timeline_meta:{user_id}             # Hash: タイムライン メタデータ
```

#### 1.2 Cloud Run Analytics Service 拡張
```python
# 新規エンドポイント
POST /follow-user                   # フォロー/解除
GET /user-follows/{user_id}         # フォロー状態取得
GET /followers/{user_id}            # フォロワー取得
GET /timeline/{user_id}             # パーソナルタイムライン
GET /global-timeline                # グローバルタイムライン
```

### Phase 2: タイムライン生成 + ファンアウト処理

#### 2.1 書き込み時タイムライン生成
```python
# カウントダウン作成/更新時
def fan_out_to_followers(user_id, countdown_data):
    """フォロワーのタイムラインに配信"""
    followers = redis.smembers(f"user_followers:{user_id}")
    
    for follower_id in followers:
        # 各フォロワーのタイムラインに追加
        redis.zadd(f"timeline:{follower_id}", {
            countdown_data['id']: countdown_data['timestamp']
        })
        
        # タイムライン長制限（最新1000件）
        redis.zremrangebyrank(f"timeline:{follower_id}", 0, -1001)
```

#### 2.2 フォロー処理時のタイムライン同期
```python
def handle_follow_event(follower_id, target_id):
    """フォロー時に対象ユーザーの投稿をタイムラインに追加"""
    
    # 対象ユーザーの最新投稿を取得
    user_countdowns = get_user_recent_countdowns(target_id, limit=100)
    
    # フォロワーのタイムラインに追加
    timeline_data = {
        countdown['id']: countdown['timestamp'] 
        for countdown in user_countdowns
    }
    
    redis.zadd(f"timeline:{follower_id}", timeline_data)
```

### Phase 3: Flutter UI + リアルタイム更新

#### 3.1 FollowService 実装
```dart
class FollowService {
  static Future<void> toggleFollow(String targetUserId) async {
    await UnifiedAnalyticsService.sendEvent(
      type: 'follow_toggle',
      countdownId: targetUserId,
      eventData: {'action': 'toggle'},
    );
  }
  
  static Future<bool> isFollowing(String targetUserId) async {
    final response = await MVPAnalyticsClient.getUserState(
      FirebaseAuth.instance.currentUser!.uid,
      targetUserId,
    );
    return response['is_following'] ?? false;
  }
}
```

#### 3.2 TimelineStreamService 実装
```dart
class TimelineStreamService {
  static Stream<List<Countdown>> getPersonalTimelineStream({
    String? userId,
    int limit = 50,
  }) {
    final targetUserId = userId ?? FirebaseAuth.instance.currentUser!.uid;
    
    return Stream.periodic(const Duration(seconds: 3), (count) async {
      final response = await http.get(
        Uri.parse('${MVPAnalyticsClient.baseUrl}/timeline/$targetUserId?limit=$limit'),
        headers: MVPAnalyticsClient.headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['countdowns'] as List)
            .map((json) => Countdown.fromJson(json))
            .toList();
      }
      return <Countdown>[];
    }).asyncMap((future) => future);
  }
}
```

### Phase 4: 画面の移行

#### 4.1 simple_home_screen.dart 更新
```dart
// 変更前（141行目）
stream: SimpleStreamService.getCountdownsStream(limit: 50),

// 変更後
stream: TimelineStreamService.getPersonalTimelineStream(limit: 50),
```

#### 4.2 profile_screen.dart 更新
```dart
// 変更前（166行目）
stream: OptimizedStreamService.getBatchedCountdownsStream(
  limit: 50,
  batchInterval: const Duration(seconds: 3),
),

// 変更後
stream: TimelineStreamService.getPersonalTimelineStream(
  userId: widget.userId, // プロフィール画面の場合
  limit: 50,
),
```

## 🚀 実装順序

1. **Phase 1**: Redis + API（1-2日）
2. **Phase 2**: ファンアウト処理（2-3日）  
3. **Phase 3**: Flutter サービス（1-2日）
4. **Phase 4**: UI移行（1日）

## 📊 期待効果

### パフォーマンス改善
- **読み取り時間**: O(フォロワー数) → O(1)
- **ネットワーク使用量**: 90%削減
- **クライアント側処理**: 95%削減

### スケーラビリティ
- 10万フォロワーでも一定のパフォーマンス
- Redis による高速アクセス（1-5ms）
- 統一パイプラインによる処理分散

### コスト効率
- Firestore読み取り料金: 98%削減継続
- クライアント側CPU使用量: 大幅削減
- サーバーサイド処理最適化

## 🔧 技術詳細

### 使用する既存コンポーネント
- **UnifiedAnalyticsService**: イベント送信
- **MVPAnalyticsClient**: API通信
- **Redis Connection Pool**: 高速データアクセス
- **統一パイプライン**: 非同期処理

### 新規追加コンポーネント
- **FollowService**: フォロー管理
- **TimelineStreamService**: タイムライン配信
- **ファンアウト処理**: 書き込み時生成

この計画により、現在のアーキテクチャの利点を活かしながら、スケーラブルなソーシャル機能を効率的に実装できます。