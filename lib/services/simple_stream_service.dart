import 'dart:async';
import '../models/countdown.dart';
import 'mvp_analytics_client.dart';

class SimpleStreamService {
  static Timer? _refreshTimer;
  static final StreamController<List<Countdown>> _streamController = StreamController<List<Countdown>>.broadcast();

  /// 【移行完了】バックエンドAPI経由のカウントダウンストリーム
  /// 
  /// 🚀 Firestore直接読み取りを完全排除
  /// ⚡ Cloud Run + Redis からの高速データ取得
  /// 💡 定期的なポーリングでリアルタイム性を維持
  static Stream<List<Countdown>> getCountdownsStream({
    String? category,
    int limit = 50,
  }) {
    print('SimpleStreamService - Starting API-based stream with category: $category, limit: $limit');
    
    // 既存のタイマーをクリア
    _refreshTimer?.cancel();
    
    // 初回データ取得
    _fetchAndEmitCountdowns(category, limit);
    
    // 定期的なデータ更新（5秒間隔）
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _fetchAndEmitCountdowns(category, limit);
    });
    
    return _streamController.stream;
  }

  /// バックエンドAPIからデータを取得してストリームに流す
  static Future<void> _fetchAndEmitCountdowns(String? category, int limit) async {
    try {
      final countdownsData = await MVPAnalyticsClient.getCountdowns(
        category: category,
        limit: limit,
      );
      
      print('SimpleStreamService - Received ${countdownsData.length} countdowns from API');
      
      final countdowns = countdownsData.map((data) {
        try {
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
            recentCommentsCount: 0, // バックエンドから取得するか計算
            recentLikesCount: 0,
            recentViewsCount: 0,
          );
        } catch (e) {
          print('SimpleStreamService - Error creating countdown from API data: $e');
          // エラーが発生した場合はスキップ
          return null;
        }
      }).where((countdown) => countdown != null).cast<Countdown>().toList();
      
      print('SimpleStreamService - Successfully created ${countdowns.length} countdown objects');
      _streamController.add(countdowns);
      
    } catch (e) {
      print('SimpleStreamService - Error fetching countdowns: $e');
      _streamController.add([]); // フォールバック
    }
  }

  /// 【移行完了】バックエンドAPI経由のコメントストリーム
  static Stream<List<Map<String, dynamic>>> getCommentsStream(String countdownId) {
    final commentsController = StreamController<List<Map<String, dynamic>>>.broadcast();
    Timer? commentsTimer;
    
    // 初回データ取得
    _fetchAndEmitComments(countdownId, commentsController);
    
    // 定期的なデータ更新（10秒間隔）
    commentsTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _fetchAndEmitComments(countdownId, commentsController);
    });
    
    // ストリーム終了時のクリーンアップ
    commentsController.onCancel = () {
      commentsTimer?.cancel();
    };
    
    return commentsController.stream;
  }
  
  /// コメントデータを取得してストリームに流す
  static Future<void> _fetchAndEmitComments(String countdownId, StreamController<List<Map<String, dynamic>>> controller) async {
    try {
      final comments = await MVPAnalyticsClient.getComments(countdownId);
      controller.add(comments);
    } catch (e) {
      print('SimpleStreamService - Error fetching comments: $e');
      controller.add([]); // フォールバック
    }
  }

  /// リソースクリーンアップ
  static void dispose() {
    _refreshTimer?.cancel();
    _streamController.close();
  }
}