import 'dart:async';
import '../models/countdown.dart';
import '../models/comment.dart';
import 'mvp_analytics_client.dart';

class OptimizedStreamService {
  // キャッシュ用のStreamController
  static final Map<String, StreamController<List<Countdown>>> _countdownStreamControllers = {};
  static final Map<String, StreamController<List<Comment>>> _commentStreamControllers = {};
  
  // キャッシュされたデータ
  static final Map<String, List<Countdown>> _countdownCache = {};
  static final Map<String, List<Comment>> _commentCache = {};
  
  // 最後の更新時間
  static final Map<String, DateTime> _lastUpdateTime = {};
  
  // ポーリング用タイマー
  static final Map<String, Timer> _pollingTimers = {};
  
  // キャッシュの有効期間（秒）
  static const int cacheValidityDuration = 10;

  /// 【移行完了】最適化されたカウントダウンストリーム（バックエンドAPI経由）
  static Stream<List<Countdown>> getOptimizedCountdownsStream({
    String? category,
    int limit = 20,
  }) {
    final key = 'countdowns_${category ?? 'all'}_$limit';
    
    // 既存のストリームがあれば再利用
    if (_countdownStreamControllers.containsKey(key)) {
      return _countdownStreamControllers[key]!.stream;
    }
    
    // 新しいStreamControllerを作成
    final controller = StreamController<List<Countdown>>.broadcast(
      onCancel: () {
        _countdownStreamControllers.remove(key);
        _countdownCache.remove(key);
        _lastUpdateTime.remove(key);
        _pollingTimers[key]?.cancel();
        _pollingTimers.remove(key);
      },
    );
    
    _countdownStreamControllers[key] = controller;
    
    // バックエンドAPIからのストリームを開始
    _startOptimizedCountdownStream(key, category, limit, controller);
    
    return controller.stream;
  }
  
  static void _startOptimizedCountdownStream(
    String key,
    String? category,
    int limit,
    StreamController<List<Countdown>> controller,
  ) {
    // 初回データ取得
    _fetchOptimizedCountdowns(key, category, limit, controller);
    
    // 定期的なポーリング（最適化されたインターバル）
    final timer = Timer.periodic(Duration(seconds: cacheValidityDuration), (_) {
      _fetchOptimizedCountdowns(key, category, limit, controller);
    });
    
    _pollingTimers[key] = timer;
  }
  
  static Future<void> _fetchOptimizedCountdowns(
    String key,
    String? category,
    int limit,
    StreamController<List<Countdown>> controller,
  ) async {
    try {
      final now = DateTime.now();
      final lastUpdate = _lastUpdateTime[key];
      
      // キャッシュが有効な場合はキャッシュから返す
      if (lastUpdate != null && 
          now.difference(lastUpdate).inSeconds < cacheValidityDuration &&
          _countdownCache.containsKey(key)) {
        if (!controller.isClosed) {
          controller.add(_countdownCache[key]!);
        }
        return;
      }
      
      // バックエンドAPIからデータを取得
      final countdownsData = await MVPAnalyticsClient.getCountdowns(
        category: category,
        limit: limit,
      );
      
      final countdowns = countdownsData.map((data) {
        return Countdown(
          id: data['id'] as String,
          eventName: data['eventName'] as String? ?? '無題',
          description: data['description'] as String?,
          eventDate: data['eventDate'] != null ? DateTime.parse(data['eventDate'] as String) : DateTime.now(),
          category: data['category'] as String? ?? 'その他',
          imageUrl: data['imageUrl'] as String?,
          creatorId: data['creatorId'] as String? ?? 'unknown',
          participantsCount: data['participantsCount'] as int? ?? 0,
          likesCount: data['likesCount'] as int? ?? 0,
          commentsCount: data['commentsCount'] as int? ?? 0,
          viewsCount: data['viewsCount'] as int? ?? 0,
          recentCommentsCount: 0,
          recentLikesCount: 0,
          recentViewsCount: 0,
          commentCount: data['commentsCount'] as int? ?? 0,
        );
      }).toList();
      
      // キャッシュ更新
      _countdownCache[key] = countdowns;
      _lastUpdateTime[key] = now;
      
      if (!controller.isClosed) {
        controller.add(countdowns);
      }
      
    } catch (e) {
      print('OptimizedStreamService - Error fetching countdowns: $e');
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  /// 【移行完了】最適化されたコメントストリーム（バックエンドAPI経由）
  static Stream<List<Comment>> getOptimizedCommentsStream({
    required String countdownId,
    int limit = 50,
  }) {
    final key = 'comments_${countdownId}_$limit';
    
    if (_commentStreamControllers.containsKey(key)) {
      return _commentStreamControllers[key]!.stream;
    }
    
    final controller = StreamController<List<Comment>>.broadcast(
      onCancel: () {
        _commentStreamControllers.remove(key);
        _commentCache.remove(key);
        _lastUpdateTime.remove(key);
        _pollingTimers[key]?.cancel();
        _pollingTimers.remove(key);
      },
    );
    
    _commentStreamControllers[key] = controller;
    
    _startOptimizedCommentStream(key, countdownId, limit, controller);
    
    return controller.stream;
  }
  
  static void _startOptimizedCommentStream(
    String key,
    String countdownId,
    int limit,
    StreamController<List<Comment>> controller,
  ) {
    // 初回データ取得
    _fetchOptimizedComments(key, countdownId, limit, controller);
    
    // 定期的なポーリング
    final timer = Timer.periodic(Duration(seconds: cacheValidityDuration * 2), (_) {
      _fetchOptimizedComments(key, countdownId, limit, controller);
    });
    
    _pollingTimers[key] = timer;
  }

  static Future<void> _fetchOptimizedComments(
    String key,
    String countdownId,
    int limit,
    StreamController<List<Comment>> controller,
  ) async {
    try {
      final now = DateTime.now();
      final lastUpdate = _lastUpdateTime[key];
      
      // キャッシュが有効な場合はキャッシュから返す
      if (lastUpdate != null && 
          now.difference(lastUpdate).inSeconds < cacheValidityDuration &&
          _commentCache.containsKey(key)) {
        if (!controller.isClosed) {
          controller.add(_commentCache[key]!);
        }
        return;
      }
      
      // バックエンドAPIからコメントを取得
      final commentsData = await MVPAnalyticsClient.getComments(countdownId, limit: limit);
      
      final comments = commentsData.map((data) {
        return Comment(
          id: data['id'] as String,
          countdownId: data['countdownId'] as String,
          content: data['content'] as String,
          userId: data['userId'] as String,
          userName: data['userName'] as String? ?? '匿名',
          userAvatarUrl: data['userAvatarUrl'] as String?,
          createdAt: data['createdAt'] != null ? DateTime.parse(data['createdAt'] as String) : DateTime.now(),
          likesCount: data['likesCount'] as int? ?? 0,
        );
      }).toList();
      
      // キャッシュ更新
      _commentCache[key] = comments;
      _lastUpdateTime[key] = now;
      
      if (!controller.isClosed) {
        controller.add(comments);
      }
      
    } catch (e) {
      print('OptimizedStreamService - Error fetching comments: $e');
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  /// キャッシュをクリア
  static void clearCache() {
    _countdownCache.clear();
    _commentCache.clear();
    _lastUpdateTime.clear();
  }
  
  /// 特定のキーのキャッシュをクリア
  static void clearCacheForKey(String key) {
    _countdownCache.remove(key);
    _commentCache.remove(key);
    _lastUpdateTime.remove(key);
  }

  /// リソースをクリーンアップ
  static void dispose() {
    // すべてのタイマーを停止
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
    
    // すべてのStreamControllerを閉じる
    for (final controller in _countdownStreamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _countdownStreamControllers.clear();
    
    for (final controller in _commentStreamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _commentStreamControllers.clear();
    
    clearCache();
  }
}