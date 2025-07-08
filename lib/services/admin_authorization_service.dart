import 'package:firebase_auth/firebase_auth.dart';
import 'moderation_logs_service.dart';

/// 管理者認証・認可サービス
/// 
/// 🛡️ 管理者操作の権限チェックと認証を管理
/// 📋 操作ごとの権限レベルを定義
/// 🔍 不正アクセス試行を検出・記録
class AdminAuthorizationService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 管理者権限レベル
  static const Map<String, int> adminLevels = {
    'viewer': 1,        // 閲覧のみ
    'moderator': 2,     // 基本的なモデレーション
    'admin': 3,         // 高度な管理操作
    'superadmin': 4,    // 全権限
  };

  /// 操作に必要な権限レベル
  static const Map<String, int> requiredPermissions = {
    // 閲覧系操作
    'view_reports': 1,
    'view_audit_logs': 1,
    'view_users': 1,
    'view_content': 1,
    
    // 基本モデレーション
    'moderate_content': 2,
    'hide_content': 2,
    'warn_user': 2,
    'resolve_report': 2,
    
    // 高度な管理操作
    'ban_user': 3,
    'delete_content': 3,
    'delete_user': 3,
    'mass_action': 3,
    
    // システム管理
    'manage_admins': 4,
    'system_settings': 4,
    'audit_log_admin': 4,
  };

  /// 現在のユーザーが管理者かチェック
  static Future<bool> isAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final idTokenResult = await user.getIdTokenResult();
      final role = idTokenResult.claims?['role'] as String?;
      return adminLevels.containsKey(role);
    } catch (e) {
      print('AdminAuthorizationService - Error checking admin status: $e');
      return false;
    }
  }

  /// 現在のユーザーの権限レベルを取得
  static Future<int> getCurrentPermissionLevel() async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    try {
      final idTokenResult = await user.getIdTokenResult();
      final role = idTokenResult.claims?['role'] as String?;
      return adminLevels[role] ?? 0;
    } catch (e) {
      print('AdminAuthorizationService - Error getting permission level: $e');
      return 0;
    }
  }

  /// 現在のユーザーの役割を取得
  static Future<String?> getCurrentRole() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final idTokenResult = await user.getIdTokenResult();
      return idTokenResult.claims?['role'] as String?;
    } catch (e) {
      print('AdminAuthorizationService - Error getting role: $e');
      return null;
    }
  }

  /// 特定の操作に対する権限をチェック
  static Future<bool> checkPermission(String action) async {
    final requiredLevel = requiredPermissions[action];
    if (requiredLevel == null) {
      print('AdminAuthorizationService - Unknown action: $action');
      return false;
    }

    final currentLevel = await getCurrentPermissionLevel();
    final hasPermission = currentLevel >= requiredLevel;

    // 権限チェック結果を監査ログに記録
    await _logPermissionCheck(action, hasPermission, currentLevel, requiredLevel);

    return hasPermission;
  }

  /// 管理者操作の実行前認証・認可チェック
  static Future<AuthorizationResult> authorizeAdminAction({
    required String action,
    required String targetType,
    required String targetId,
    String? reason,
    Map<String, dynamic>? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      await _logUnauthorizedAttempt(action, targetType, targetId, 'Not authenticated');
      return AuthorizationResult.denied('認証が必要です');
    }

    // 基本的な管理者権限チェック
    if (!await isAdmin()) {
      await _logUnauthorizedAttempt(action, targetType, targetId, 'Not an admin');
      return AuthorizationResult.denied('管理者権限が必要です');
    }

    // 特定操作の権限チェック
    if (!await checkPermission(action)) {
      final currentRole = await getCurrentRole();
      await _logUnauthorizedAttempt(
        action, 
        targetType, 
        targetId, 
        'Insufficient permissions (role: $currentRole)'
      );
      return AuthorizationResult.denied('この操作を実行する権限がありません');
    }

    // 高リスク操作の追加チェック
    if (_isHighRiskAction(action)) {
      final additionalCheckResult = await _performAdditionalSecurityChecks(
        action, 
        targetType, 
        targetId, 
        user
      );
      if (!additionalCheckResult.success) {
        return additionalCheckResult;
      }
    }

    // 認可成功を記録
    await ModerationLogsService.logAdminAction(
      action: 'authorization_granted',
      targetType: 'authorization',
      targetId: '${action}_${targetType}_$targetId',
      reason: 'Authorization granted for admin action',
      metadata: {
        'authorized_action': action,
        'target_type': targetType,
        'target_id': targetId,
        'user_role': await getCurrentRole(),
        'permission_level': await getCurrentPermissionLevel(),
        if (context != null) 'context': context,
      },
    );

    return AuthorizationResult.granted();
  }

  /// 権限チェック結果を監査ログに記録
  static Future<void> _logPermissionCheck(
    String action, 
    bool hasPermission, 
    int currentLevel, 
    int requiredLevel
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await ModerationLogsService.logAdminAction(
      action: 'permission_check',
      targetType: 'authorization',
      targetId: action,
      reason: hasPermission ? 'Permission granted' : 'Permission denied',
      metadata: {
        'checked_action': action,
        'has_permission': hasPermission,
        'current_level': currentLevel,
        'required_level': requiredLevel,
        'user_role': await getCurrentRole(),
      },
    );
  }

  /// 不正アクセス試行を記録
  static Future<void> _logUnauthorizedAttempt(
    String action, 
    String targetType, 
    String targetId, 
    String reason
  ) async {
    final user = _auth.currentUser;
    
    await ModerationLogsService.logAdminAction(
      action: 'unauthorized_attempt',
      targetType: 'security',
      targetId: '${action}_${targetType}_$targetId',
      reason: 'Unauthorized access attempt: $reason',
      metadata: {
        'attempted_action': action,
        'target_type': targetType,
        'target_id': targetId,
        'failure_reason': reason,
        'user_uid': user?.uid,
        'user_email': user?.email,
        'severity': 'HIGH',
        'security_alert': true,
      },
    );
  }

  /// 高リスク操作かチェック
  static bool _isHighRiskAction(String action) {
    const highRiskActions = [
      'ban_user',
      'delete_user',
      'delete_content',
      'mass_action',
      'manage_admins',
      'system_settings',
    ];
    return highRiskActions.contains(action);
  }

  /// 高リスク操作の追加セキュリティチェック
  static Future<AuthorizationResult> _performAdditionalSecurityChecks(
    String action,
    String targetType,
    String targetId,
    User user,
  ) async {
    // IPアドレスチェック（実装例）
    // 実際の実装では、許可されたIPアドレスリストと照合
    
    // 時間帯チェック（実装例）
    final now = DateTime.now();
    final hour = now.hour;
    if (hour < 6 || hour > 22) {
      await _logSecurityViolation(
        action, 
        targetType, 
        targetId, 
        'High-risk operation attempted outside business hours'
      );
      return AuthorizationResult.denied('高リスク操作は営業時間内（6:00-22:00）のみ実行可能です');
    }

    // レート制限チェック（実装例）
    // 実際の実装では、Redis等を使用して操作頻度を監視

    return AuthorizationResult.granted();
  }

  /// セキュリティ違反を記録
  static Future<void> _logSecurityViolation(
    String action,
    String targetType,
    String targetId,
    String violation,
  ) async {
    await ModerationLogsService.logAdminAction(
      action: 'security_violation',
      targetType: 'security',
      targetId: '${action}_${targetType}_$targetId',
      reason: 'Security policy violation: $violation',
      metadata: {
        'attempted_action': action,
        'target_type': targetType,
        'target_id': targetId,
        'violation_type': violation,
        'severity': 'CRITICAL',
        'requires_investigation': true,
      },
    );
  }

  /// セッション有効性チェック
  static Future<bool> validateSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // トークンの更新を試行してセッションの有効性を確認
      await user.getIdToken(true);
      return true;
    } catch (e) {
      print('AdminAuthorizationService - Session validation failed: $e');
      return false;
    }
  }

  /// 管理者セッションの安全な開始
  static Future<bool> initiateAdminSession() async {
    if (!await isAdmin()) return false;

    await ModerationLogsService.logAdminAction(
      action: 'admin_session_start',
      targetType: 'session',
      targetId: _auth.currentUser?.uid ?? 'unknown',
      reason: 'Admin session initiated',
      metadata: {
        'user_role': await getCurrentRole(),
        'session_timestamp': DateTime.now().toIso8601String(),
      },
    );

    return true;
  }

  /// 管理者セッションの終了
  static Future<void> terminateAdminSession() async {
    await ModerationLogsService.logAdminAction(
      action: 'admin_session_end',
      targetType: 'session',
      targetId: _auth.currentUser?.uid ?? 'unknown',
      reason: 'Admin session terminated',
      metadata: {
        'session_end_timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}

/// 認可結果クラス
class AuthorizationResult {
  final bool success;
  final String? message;

  const AuthorizationResult._({required this.success, this.message});

  factory AuthorizationResult.granted() => const AuthorizationResult._(success: true);
  factory AuthorizationResult.denied(String message) => AuthorizationResult._(success: false, message: message);
}