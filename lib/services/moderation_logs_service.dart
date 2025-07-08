import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';

/// 管理者操作の監査ログサービス
/// 
/// 🛡️ 全ての管理者操作を記録し、法的リスクと内部不正を防ぐ
/// 📊 analytics-service経由で確実にログを保存
/// 🔍 詳細な検索・フィルタリング機能を提供
class ModerationLogsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'moderation_logs';

  /// 【統一パイプライン】管理者操作の監査ログを記録
  /// 
  /// 🚀 analytics-service経由で確実にログを保存
  /// 📋 WHO（誰が）、WHEN（いつ）、WHAT（何を）、WHY（なぜ）を記録
  static Future<bool> logAdminAction({
    required String action,
    required String targetType,
    required String targetId,
    required String reason,
    String? notes,
    Map<String, dynamic>? metadata,
    String? previousState,
    String? newState,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('管理者操作はログイン状態で実行してください');
    }

    try {
      // 詳細な監査ログデータを構築
      final logData = {
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'admin_uid': user.uid,
        'admin_email': user.email,
        'timestamp': DateTime.now().toIso8601String(),
        'ip_address': await _getClientIpAddress(),
        'user_agent': await _getUserAgent(),
        if (notes != null) 'notes': notes,
        if (metadata != null) 'metadata': metadata,
        if (previousState != null) 'previous_state': previousState,
        if (newState != null) 'new_state': newState,
        'severity': _calculateSeverity(action),
        'requires_approval': _requiresApproval(action),
      };

      // 🚀 統一パイプライン経由で監査ログを送信
      final success = await UnifiedAnalyticsService.sendEvent(
        type: 'admin_action_logged',
        data: logData,
      );

      if (success) {
        // 重要な操作は即座にローカルFirestoreにもバックアップ
        if (_isHighSeverityAction(action)) {
          await _firestore.collection(_collection).add({
            ...logData,
            'backup_timestamp': FieldValue.serverTimestamp(),
          });
        }
        
        return true;
      } else {
        throw Exception('監査ログの送信に失敗しました');
      }
    } catch (e) {
      // 監査ログの記録失敗は重大なエラー
      print('CRITICAL: Failed to log admin action: $e');
      
      // 緊急時はローカルFirestoreに直接保存
      try {
        await _firestore.collection('emergency_logs').add({
          'action': action,
          'target_type': targetType,
          'target_id': targetId,
          'reason': reason,
          'admin_uid': user.uid,
          'admin_email': user.email,
          'timestamp': FieldValue.serverTimestamp(),
          'error': e.toString(),
          'emergency_backup': true,
        });
      } catch (emergencyError) {
        print('EMERGENCY: Failed to save emergency log: $emergencyError');
      }
      
      return false;
    }
  }

  /// 【統一パイプライン】監査ログの検索・取得
  /// 
  /// 🔍 管理者は自分の操作履歴を確認可能
  /// 👥 スーパー管理者は全ての操作履歴を確認可能
  static Future<List<ModerationLog>> getModerationLogs({
    String? adminUid,
    String? targetType,
    String? targetId,
    String? action,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    String? lastDocumentId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('ログイン状態で実行してください');
    }

    try {
      // 🚀 統一パイプライン経由で監査ログを取得
      final response = await MVPAnalyticsClient.getAdminLogs(
        adminUid: adminUid,
        targetType: targetType,
        targetId: targetId,
        action: action,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        lastDocumentId: lastDocumentId,
      );

      return response.map((log) => ModerationLog.fromJson(log)).toList();
    } catch (e) {
      print('Error fetching moderation logs: $e');
      return [];
    }
  }

  /// 【統一パイプライン】管理者操作の統計情報を取得
  /// 
  /// 📊 管理者の活動状況を可視化
  /// 🔍 異常な操作パターンを検出
  static Future<Map<String, dynamic>> getAdminActivityStats({
    String? adminUid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      return await MVPAnalyticsClient.getAdminActivityStats(
        adminUid: adminUid,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      print('Error fetching admin activity stats: $e');
      return {};
    }
  }

  /// 【内部】操作の重要度を計算
  static String _calculateSeverity(String action) {
    switch (action) {
      case 'user_ban':
      case 'user_delete':
      case 'content_delete':
      case 'mass_action':
        return 'HIGH';
      case 'content_hide':
      case 'user_suspend':
      case 'content_flag':
        return 'MEDIUM';
      case 'content_review':
      case 'user_warning':
        return 'LOW';
      default:
        return 'MEDIUM';
    }
  }

  /// 【内部】操作が承認を必要とするかチェック
  static bool _requiresApproval(String action) {
    const highRiskActions = [
      'user_ban',
      'user_delete',
      'content_delete',
      'mass_action',
    ];
    return highRiskActions.contains(action);
  }

  /// 【内部】重要度の高い操作かチェック
  static bool _isHighSeverityAction(String action) {
    return _calculateSeverity(action) == 'HIGH';
  }

  /// 【内部】クライアントIPアドレスを取得
  static Future<String?> _getClientIpAddress() async {
    try {
      // 実際の実装では、HTTP requestからIPアドレスを取得
      // モバイルアプリの場合は、デバイス情報を取得
      return null; // プレースホルダー
    } catch (e) {
      return null;
    }
  }

  /// 【内部】ユーザーエージェントを取得
  static Future<String?> _getUserAgent() async {
    try {
      // 実際の実装では、デバイス情報やアプリバージョンを取得
      return null; // プレースホルダー
    } catch (e) {
      return null;
    }
  }
}

/// 監査ログのデータモデル
class ModerationLog {
  final String id;
  final String action;
  final String targetType;
  final String targetId;
  final String reason;
  final String adminUid;
  final String? adminEmail;
  final DateTime timestamp;
  final String? ipAddress;
  final String? userAgent;
  final String? notes;
  final Map<String, dynamic>? metadata;
  final String? previousState;
  final String? newState;
  final String severity;
  final bool requiresApproval;

  ModerationLog({
    required this.id,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.adminUid,
    this.adminEmail,
    required this.timestamp,
    this.ipAddress,
    this.userAgent,
    this.notes,
    this.metadata,
    this.previousState,
    this.newState,
    required this.severity,
    required this.requiresApproval,
  });

  factory ModerationLog.fromJson(Map<String, dynamic> json) {
    return ModerationLog(
      id: json['id'] ?? '',
      action: json['action'] ?? '',
      targetType: json['target_type'] ?? '',
      targetId: json['target_id'] ?? '',
      reason: json['reason'] ?? '',
      adminUid: json['admin_uid'] ?? '',
      adminEmail: json['admin_email'],
      timestamp: DateTime.parse(json['timestamp']),
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      notes: json['notes'],
      metadata: json['metadata'],
      previousState: json['previous_state'],
      newState: json['new_state'],
      severity: json['severity'] ?? 'MEDIUM',
      requiresApproval: json['requires_approval'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'admin_uid': adminUid,
      'admin_email': adminEmail,
      'timestamp': timestamp.toIso8601String(),
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'notes': notes,
      'metadata': metadata,
      'previous_state': previousState,
      'new_state': newState,
      'severity': severity,
      'requires_approval': requiresApproval,
    };
  }
}

/// 管理者操作のアクション定数
class AdminActions {
  static const String userBan = 'user_ban';
  static const String userSuspend = 'user_suspend';
  static const String userDelete = 'user_delete';
  static const String userWarning = 'user_warning';
  static const String contentHide = 'content_hide';
  static const String contentDelete = 'content_delete';
  static const String contentFlag = 'content_flag';
  static const String contentReview = 'content_review';
  static const String massAction = 'mass_action';
  static const String reportReview = 'report_review';
  static const String reportResolve = 'report_resolve';
  static const String reportReject = 'report_reject';
}

/// 管理者操作の対象タイプ定数
class AdminTargetTypes {
  static const String user = 'user';
  static const String countdown = 'countdown';
  static const String comment = 'comment';
  static const String report = 'report';
  static const String system = 'system';
}