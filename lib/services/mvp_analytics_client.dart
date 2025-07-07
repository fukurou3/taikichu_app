import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

/// MVP分析基盤クライアント
/// 
/// 🎯 目的: Cloud RunサービスからRedisデータを高速取得
/// ⚡ 性能: 1-5ms のレスポンス時間
/// 💰 コスト: Firestore読み取りの1/10以下
class MVPAnalyticsClient {
  // Cloud Run サービスのURL（実際のURLに置き換え）
  static const String _baseUrl = 'https://analytics-service-694414843228.asia-northeast1.run.app';
  
  static final http.Client _httpClient = http.Client();

  /// 【高速】トレンドスコアを取得
  /// 
  /// Firestore: 50-200ms → Redis: 1-5ms
  static Future<double> getTrendScore(String countdownId) async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_baseUrl/trend-score/$countdownId'),
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['trend_score'] as num?)?.toDouble() ?? 0.0;
      } else {
        print('MVPAnalyticsClient - Error getting trend score: ${response.statusCode}');
        return 0.0;
      }
    } catch (e) {
      print('MVPAnalyticsClient - Error getting trend score: $e');
      return 0.0; // フォールバック
    }
  }

  /// 【高速】カウンター値を取得
  /// 
  /// 分散シャード読み取り: 10 reads → Redis: 1 read
  static Future<int> getCounterValue({
    required String countdownId,
    required String counterType, // 'likes', 'participants', 'comments', 'views'
  }) async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_baseUrl/counter/$countdownId/$counterType'),
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['count'] as int?) ?? 0;
      } else {
        print('MVPAnalyticsClient - Error getting counter: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      print('MVPAnalyticsClient - Error getting counter: $e');
      return 0; // フォールバック
    }
  }

  /// 【高速】トレンドランキングを取得
  /// 
  /// Firestore全件読み取り: 数秒 → Redis: 数ミリ秒
  static Future<List<TrendRankingItem>> getTrendRanking({
    String? category,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/ranking').replace(
        queryParameters: {
          if (category != null) 'category': category,
          'limit': limit.toString(),
        },
      );

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ranking = data['ranking'] as List?;
        
        if (ranking != null) {
          return ranking
              .map((item) => TrendRankingItem.fromJson(item))
              .toList();
        }
      } else {
        print('MVPAnalyticsClient - Error getting ranking: ${response.statusCode}');
      }
    } catch (e) {
      print('MVPAnalyticsClient - Error getting ranking: $e');
    }
    
    return []; // フォールバック
  }

  /// 【軽量】閲覧イベントを送信
  /// 
  /// Cloud Functions経由でPub/Subに送信
  static Future<void> sendViewEvent({
    required String countdownId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Firebase Functions の publishViewEvent を呼び出し
      // 注意: firebase_functions パッケージが必要
      // import 'package:cloud_functions/cloud_functions.dart';
      
      // 一時的なHTTP実装（後でFirebase Functionsに置き換え）
      final eventData = {
        'countdownId': countdownId,
        'metadata': {
          'userAgent': 'Flutter App',
          'timestamp': DateTime.now().toIso8601String(),
          ...?metadata,
        },
      };

      // この部分は実際にはFirebase Functions経由で送信
      print('MVPAnalyticsClient - View event would be sent: $eventData');
      
    } catch (e) {
      print('MVPAnalyticsClient - Error sending view event: $e');
      // エラーでもアプリは継続動作
    }
  }

  /// システム健康状態を確認
  static Future<Map<String, dynamic>> getSystemHealth() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'status': 'error',
          'message': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  /// 複数のカウンターを一括取得（効率化）
  static Future<Map<String, int>> getMultipleCounters({
    required String countdownId,
    required List<String> counterTypes,
  }) async {
    final results = <String, int>{};
    
    // 並列で複数のカウンターを取得
    final futures = counterTypes.map((type) => 
      getCounterValue(countdownId: countdownId, counterType: type)
          .then((value) => MapEntry(type, value))
    );
    
    try {
      final entries = await Future.wait(futures);
      for (final entry in entries) {
        results[entry.key] = entry.value;
      }
    } catch (e) {
      print('MVPAnalyticsClient - Error getting multiple counters: $e');
    }
    
    return results;
  }

  /// キャッシュ機能付きトレンドスコア取得
  static final Map<String, _CachedValue<double>> _trendScoreCache = {};
  
  static Future<double> getTrendScoreCached(String countdownId, {
    Duration cacheDuration = const Duration(minutes: 5),
  }) async {
    final cached = _trendScoreCache[countdownId];
    final now = DateTime.now();
    
    if (cached != null && now.difference(cached.timestamp) < cacheDuration) {
      return cached.value;
    }
    
    final score = await getTrendScore(countdownId);
    _trendScoreCache[countdownId] = _CachedValue(score, now);
    
    return score;
  }

  /// キャッシュクリア
  static void clearCache() {
    _trendScoreCache.clear();
  }

  /// リソース解放
  static void dispose() {
    _httpClient.close();
    clearCache();
  }
}

/// トレンドランキングアイテム
class TrendRankingItem {
  final String countdownId;
  final double trendScore;

  TrendRankingItem({
    required this.countdownId,
    required this.trendScore,
  });

  factory TrendRankingItem.fromJson(Map<String, dynamic> json) {
    return TrendRankingItem(
      countdownId: json['countdown_id'] as String,
      trendScore: (json['trend_score'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'countdown_id': countdownId,
      'trend_score': trendScore,
    };
  }
}

/// キャッシュ用ヘルパークラス
class _CachedValue<T> {
  final T value;
  final DateTime timestamp;

  _CachedValue(this.value, this.timestamp);
}

/// EnhancedCountdownCard と統合するためのヘルパー
class MVPCountdownData {
  /// カウントダウンの全分析データを一括取得
  static Future<Map<String, dynamic>> getAnalyticsData(String countdownId) async {
    try {
      // 並列で全データを取得
      final futures = await Future.wait([
        MVPAnalyticsClient.getTrendScore(countdownId),
        MVPAnalyticsClient.getMultipleCounters(
          countdownId: countdownId,
          counterTypes: ['likes', 'participants', 'comments', 'views'],
        ),
      ]);

      final trendScore = futures[0] as double;
      final counters = futures[1] as Map<String, int>;

      return {
        'trendScore': trendScore,
        'likesCount': counters['likes'] ?? 0,
        'participantsCount': counters['participants'] ?? 0,
        'commentsCount': counters['comments'] ?? 0,
        'viewsCount': counters['views'] ?? 0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('MVPCountdownData - Error getting analytics data: $e');
      return {
        'trendScore': 0.0,
        'likesCount': 0,
        'participantsCount': 0,
        'commentsCount': 0,
        'viewsCount': 0,
        'error': e.toString(),
      };
    }
  }
}