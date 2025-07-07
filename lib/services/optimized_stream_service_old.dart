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

  /// 最適化されたコメントストリーム
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
      },
    );
    
    _commentStreamControllers[key] = controller;
    
    _startCommentStream(key, countdownId, limit, controller);
    
    return controller.stream;
  }
  
  static void _startCommentStream(
    String key,
    String countdownId,
    int limit,
    StreamController<List<Comment>> controller,
  ) {
    _firestore
        .collection('comments')
        .where('countdownId', isEqualTo: countdownId)
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots()
        .listen(
      (snapshot) {
        final now = DateTime.now();
        final lastUpdate = _lastUpdateTime[key];
        
        // 新しいドキュメントがある場合のみ更新
        final hasNewDocuments = snapshot.docChanges.any(
          (change) => change.type == DocumentChangeType.added,
        );
        
        if (!hasNewDocuments &&
            lastUpdate != null && 
            now.difference(lastUpdate).inSeconds < cacheValidityDuration &&
            _commentCache.containsKey(key)) {
          return;
        }
        
        final comments = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Comment(
            id: doc.id,
            countdownId: data['countdownId'] as String,
            content: data['content'] as String,
            authorId: data['authorId'] as String,
            authorName: data['authorName'] as String? ?? 'ユーザー',
            createdAt: (data['createdAt'] as Timestamp).toDate(),
            likesCount: data['likesCount'] as int? ?? 0,
            repliesCount: data['repliesCount'] as int? ?? 0,
          );
        }).toList();
        
        // クライアント側でソート（Firestoreインデックスの制約回避）
        comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        
        _commentCache[key] = comments;
        _lastUpdateTime[key] = now;
        
        if (!controller.isClosed) {
          controller.add(comments);
        }
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );
  }

  /// バッチ更新でリアルタイム性を保ちつつパフォーマンス向上
  static Stream<List<Countdown>> getBatchedCountdownsStream({
    String? category,
    int limit = 20,
    Duration batchInterval = const Duration(seconds: 2),
  }) {
    return getOptimizedCountdownsStream(category: category, limit: limit)
        .transform(StreamTransformer<List<Countdown>, List<Countdown>>.fromBind(
          (stream) {
            return stream
                .distinct() // 重複する更新を除去
                .debounceTime(batchInterval); // 指定時間内の更新をバッチ化
          },
        ));
  }

  /// キャッシュをクリア
  static void clearCache({String? specificKey}) {
    if (specificKey != null) {
      _countdownCache.remove(specificKey);
      _commentCache.remove(specificKey);
      _lastUpdateTime.remove(specificKey);
    } else {
      _countdownCache.clear();
      _commentCache.clear();
      _lastUpdateTime.clear();
    }
  }

  /// すべてのストリームを閉じる
  static void disposeAllStreams() {
    for (final controller in _countdownStreamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    
    for (final controller in _commentStreamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    
    _countdownStreamControllers.clear();
    _commentStreamControllers.clear();
    clearCache();
  }
}

/// Streamの拡張メソッド
extension StreamExtensions<T> on Stream<T> {
  /// 重複する値をフィルター
  Stream<T> distinct() {
    T? previous;
    return where((current) {
      if (previous == null || previous != current) {
        previous = current;
        return true;
      }
      return false;
    });
  }
  
  /// デバウンス処理
  Stream<T> debounceTime(Duration duration) {
    late StreamController<T> controller;
    Timer? timer;
    
    controller = StreamController<T>(
      onListen: () {
        listen(
          (data) {
            timer?.cancel();
            timer = Timer(duration, () {
              if (!controller.isClosed) {
                controller.add(data);
              }
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            controller.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    
    return controller.stream;
  }
}