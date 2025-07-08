import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

/// 統一分析サービス
/// 
/// 🎯 目的: 全てのイベントを統一パイプラインで処理
/// ⚡ 特徴: 直接送信とPub/Sub送信の両対応
/// 🛡️ 安全性: 重複防止・エラーハンドリング完備
class UnifiedAnalyticsService {
  static const String _cloudRunUrl = 'https://analytics-service-694414843228.asia-northeast1.run.app';
  static final http.Client _httpClient = http.Client();
  static final Uuid _uuid = Uuid();
  static String? _sessionId;
  
  /// セッションID取得（アプリ起動時に一度生成）
  static String get sessionId {
    _sessionId ??= _uuid.v4();
    return _sessionId!;
  }

  /// 統一イベント送信（メインメソッド）
  /// 
  /// [type] イベントタイプ（like_added, comment_added等）
  /// [countdownId] 対象カウントダウンID
  /// [metadata] 追加メタデータ
  /// [forcePubSub] Pub/Sub経由を強制（デフォルト: false）
  static Future<bool> sendEvent({
    required String type,
    required String countdownId,
    Map<String, dynamic>? metadata,
    bool forcePubSub = false,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      final eventData = {
        'countdownId': countdownId,
        'userId': user?.uid,
        ...?metadata,
      };
      
      // 高速パス: Cloud Run直接送信
      if (!forcePubSub) {
        final success = await _sendDirectToCloudRun(type, eventData);
        if (success) {
          print('UnifiedAnalyticsService - Event sent via direct path: $type');
          return true;
        }
      }
      
      // フォールバック: 統一HTTPハンドラー経由
      print('UnifiedAnalyticsService - Fallback to unified handler: $type');
      return await _sendViaUnifiedHandler(type, eventData, metadata);
      
    } catch (e) {
      print('UnifiedAnalyticsService - Error sending event: $e');
      return false;
    }
  }

  /// Cloud Run直接送信（高速パス）
  static Future<bool> _sendDirectToCloudRun(String eventType, Map<String, dynamic> eventData) async {
    try {
      final event = {
        'eventId': _generateEventId(eventType, eventData['countdownId']),
        'type': eventType,
        'countdownId': eventData['countdownId'],
        'userId': eventData['userId'],
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'source': 'client_direct',
          'session_id': sessionId,
          'app_version': '1.0.0',
          ...?eventData,
        },
      };
      
      final response = await _httpClient
          .post(
            Uri.parse('$_cloudRunUrl/events'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'Flutter-App/1.0.0',
            },
            body: jsonEncode(event),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      } else {
        print('UnifiedAnalyticsService - Direct send failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('UnifiedAnalyticsService - Direct send error: $e');
      return false;
    }
  }

  /// 統一HTTPハンドラー経由送信（フォールバック）
  static Future<bool> _sendViaUnifiedHandler(String eventType, Map<String, dynamic> eventData, Map<String, dynamic>? metadata) async {
    try {
      // 新しい統一HTTPハンドラーを使用
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('unifiedEventHandler');
      
      final result = await callable.call({
        'eventType': eventType,
        'eventData': eventData,
        'metadata': {
          'source': 'client_unified_handler',
          'session_id': sessionId,
          'app_version': '1.0.0',
          'userAgent': 'Flutter-App/1.0.0',
          ...?metadata,
        },
      });
      
      return result.data['success'] == true;
    } catch (e) {
      print('UnifiedAnalyticsService - Unified handler error: $e');
      
      // 最終フォールバック: 従来のpublishViewEventを使用
      if (eventType == 'view') {
        return await _sendViaLegacyViewEvent(eventData, metadata);
      }
      
      return false;
    }
  }
  
  /// レガシーview eventエンドポイント（最終フォールバック）
  static Future<bool> _sendViaLegacyViewEvent(Map<String, dynamic> eventData, Map<String, dynamic>? metadata) async {
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('publishViewEvent');
      
      final result = await callable.call({
        'countdownId': eventData['countdownId'],
        'metadata': {
          'source': 'client_legacy_fallback',
          'session_id': sessionId,
          ...?metadata,
        },
      });
      
      return result.data['success'] == true;
    } catch (e) {
      print('UnifiedAnalyticsService - Legacy view event error: $e');
      return false;
    }
  }

  /// Firebase ID Token取得
  static Future<String?> _getIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (e) {
      print('UnifiedAnalyticsService - Error getting ID token: $e');
      return null;
    }
  }

  /// イベントID生成（重複防止）
  static String _generateEventId(String type, String countdownId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4().substring(0, 8);
    return '${type}_${countdownId}_${timestamp}_$random';
  }

  // === 便利メソッド群 ===

  /// いいねイベント送信
  static Future<bool> sendLikeEvent(String countdownId, bool isAdding) async {
    return await sendEvent(
      type: isAdding ? 'like_added' : 'like_removed',
      countdownId: countdownId,
      metadata: {'action': isAdding ? 'add' : 'remove'},
    );
  }

  /// コメントイベント送信
  static Future<bool> sendCommentEvent(String countdownId, {String? commentId}) async {
    return await sendEvent(
      type: 'comment_added',
      countdownId: countdownId,
      metadata: {
        if (commentId != null) 'comment_id': commentId,
      },
    );
  }

  /// 参加イベント送信
  static Future<bool> sendParticipationEvent(String countdownId, bool isJoining) async {
    return await sendEvent(
      type: isJoining ? 'participation_added' : 'participation_removed',
      countdownId: countdownId,
      metadata: {'action': isJoining ? 'join' : 'leave'},
    );
  }

  /// 閲覧イベント送信
  static Future<bool> sendViewEvent(String countdownId, {Map<String, dynamic>? viewMetadata}) async {
    return await sendEvent(
      type: 'view',
      countdownId: countdownId,
      metadata: {
        'view_duration': 0, // 実際の閲覧時間を設定
        'source_screen': 'home', // 閲覧元画面
        ...?viewMetadata,
      },
    );
  }

  /// フォロー/アンフォローイベント送信
  static Future<bool> sendFollowEvent(String targetUserId, {String? action}) async {
    return await sendEvent(
      type: 'follow_toggle',
      countdownId: targetUserId, // targetUserIdをcountdownIdパラメータで送信
      metadata: {
        'action': action ?? 'toggle',
        'targetUserId': targetUserId,
      },
    );
  }

  /// カウントダウン作成イベント送信
  static Future<bool> sendCountdownCreatedEvent(String countdownId, {Map<String, dynamic>? countdownData}) async {
    return await sendEvent(
      type: 'countdown_created',
      countdownId: countdownId,
      metadata: {
        'action': 'create',
        'source': 'user_creation',
        'eventName': countdownData?['eventName'],
        'eventDate': countdownData?['eventDate'],
        'category': countdownData?['category'],
        ...?countdownData,
      },
    );
  }
  
  /// レポート作成イベント送信
  static Future<bool> sendReportCreatedEvent(String targetId, String targetType, String reportType, {Map<String, dynamic>? reportData}) async {
    return await sendEvent(
      type: 'report_created',
      countdownId: targetId, // targetIdをcountdownIdパラメータで送信
      metadata: {
        'targetType': targetType,
        'targetId': targetId,
        'reportType': reportType,
        'source': 'user_report',
        ...?reportData,
      },
    );
  }
  
  /// モデレーションアクションイベント送信
  static Future<bool> sendModerationActionEvent(String targetId, String actionType, String moderatorId, {Map<String, dynamic>? actionData}) async {
    return await sendEvent(
      type: 'moderation_action',
      countdownId: targetId, // targetIdをcountdownIdパラメータで送信
      metadata: {
        'targetId': targetId,
        'actionType': actionType,
        'moderatorId': moderatorId,
        'source': 'moderation_system',
        ...?actionData,
      },
    );
  }

  /// バッチイベント送信（複数イベントの一括送信）
  static Future<List<bool>> sendBatchEvents(List<Map<String, dynamic>> events) async {
    try {
      // 統一バッチハンドラーを使用
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('batchEventHandler');
      
      final result = await callable.call({
        'events': events.map((event) => {
          'eventType': event['type'],
          'eventData': {
            'countdownId': event['countdownId'],
            'userId': FirebaseAuth.instance.currentUser?.uid,
            ...?event['metadata'],
          },
        }).toList(),
        'metadata': {
          'source': 'client_batch_handler',
          'session_id': sessionId,
          'app_version': '1.0.0',
          'batchSize': events.length,
        },
      });
      
      if (result.data['success'] == true) {
        final results = result.data['results'] as List<dynamic>;
        return results.map((r) => r['success'] == true).toList().cast<bool>();
      } else {
        // フォールバック: 個別送信
        final futures = events.map((event) => sendEvent(
          type: event['type'],
          countdownId: event['countdownId'],
          metadata: event['metadata'],
        ));
        
        return await Future.wait(futures);
      }
    } catch (e) {
      print('UnifiedAnalyticsService - Batch event error: $e');
      
      // フォールバック: 個別送信
      final futures = events.map((event) => sendEvent(
        type: event['type'],
        countdownId: event['countdownId'],
        metadata: event['metadata'],
      ));
      
      return await Future.wait(futures);
    }
  }

  /// システム健康状態チェック
  static Future<Map<String, dynamic>> checkSystemHealth() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_cloudRunUrl/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// 統計情報取得
  static Future<Map<String, dynamic>> getAnalyticsStats(String countdownId) async {
    try {
      // 並列で複数の統計を取得
      final futures = await Future.wait([
        _httpClient.get(Uri.parse('$_cloudRunUrl/trend-score/$countdownId')),
        _httpClient.get(Uri.parse('$_cloudRunUrl/counter/$countdownId/likes')),
        _httpClient.get(Uri.parse('$_cloudRunUrl/counter/$countdownId/comments')),
        _httpClient.get(Uri.parse('$_cloudRunUrl/counter/$countdownId/participants')),
        _httpClient.get(Uri.parse('$_cloudRunUrl/counter/$countdownId/views')),
      ]);

      final results = <String, dynamic>{};
      
      if (futures[0].statusCode == 200) {
        final data = jsonDecode(futures[0].body);
        results['trendScore'] = data['trend_score'];
      }
      
      final counterTypes = ['likes', 'comments', 'participants', 'views'];
      for (int i = 1; i < futures.length; i++) {
        if (futures[i].statusCode == 200) {
          final data = jsonDecode(futures[i].body);
          results['${counterTypes[i-1]}Count'] = data['count'];
        }
      }
      
      return results;
    } catch (e) {
      print('UnifiedAnalyticsService - Error getting stats: $e');
      return {};
    }
  }

  /// リソース解放
  static void dispose() {
    _httpClient.close();
  }
}

/// 統一分析イベント型定義
class UnifiedEvent {
  final String eventId;
  final String type;
  final String countdownId;
  final String? userId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  UnifiedEvent({
    required this.eventId,
    required this.type,
    required this.countdownId,
    this.userId,
    required this.timestamp,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'type': type,
      'countdownId': countdownId,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory UnifiedEvent.fromJson(Map<String, dynamic> json) {
    return UnifiedEvent(
      eventId: json['eventId'],
      type: json['type'],
      countdownId: json['countdownId'],
      userId: json['userId'],
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'] ?? {},
    );
  }
}

/// 統一分析のレスポンス型定義
class UnifiedAnalyticsResponse {
  final bool success;
  final String? eventId;
  final String? eventType;
  final String? countdownId;
  final double executionTime;
  final Map<String, dynamic>? additionalData;
  final String? error;

  UnifiedAnalyticsResponse({
    required this.success,
    this.eventId,
    this.eventType,
    this.countdownId,
    required this.executionTime,
    this.additionalData,
    this.error,
  });

  factory UnifiedAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    return UnifiedAnalyticsResponse(
      success: json['success'] ?? false,
      eventId: json['event_id'],
      eventType: json['event_type'],
      countdownId: json['countdown_id'],
      executionTime: (json['execution_time'] as num?)?.toDouble() ?? 0.0,
      additionalData: json,
      error: json['error'],
    );
  }
}