import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../lib/services/moderation_logs_service.dart';

class AdminApiService {
  // Cloud Run analytics service URL
  static const String baseUrl = 'https://analytics-service-694414843228.asia-northeast1.run.app';
  
  final String? _authToken;
  
  AdminApiService(this._authToken);
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// コンテンツのモデレーション（監査ログ付き）
  Future<ApiResponse<Map<String, dynamic>>> moderateContent({
    required String contentId,
    required String contentType,
    required String newStatus,
    required String reason,
    String? notes,
  }) async {
    try {
      // 【重要】操作前に監査ログを記録
      final auditLogged = await ModerationLogsService.logAdminAction(
        action: AdminActions.contentReview,
        targetType: contentType,
        targetId: contentId,
        reason: reason,
        notes: notes,
        newState: newStatus,
        metadata: {
          'moderation_type': 'content_moderation',
          'action_source': 'admin_interface',
        },
      );

      if (!auditLogged) {
        return ApiResponse.error('監査ログの記録に失敗しました。操作を中止します。');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/admin/contents/moderate'),
        headers: _headers,
        body: jsonEncode({
          'contentId': contentId,
          'contentType': contentType,
          'newStatus': newStatus,
          'reason': reason,
          if (notes != null) 'notes': notes,
          'audit_logged': true, // 監査ログ記録済みフラグ
        }),
      );

      if (response.statusCode == 200) {
        // 成功時は追加の監査ログを記録
        await ModerationLogsService.logAdminAction(
          action: '${AdminActions.contentReview}_completed',
          targetType: contentType,
          targetId: contentId,
          reason: '操作完了',
          metadata: {
            'operation_result': 'success',
            'response_status': response.statusCode,
          },
        );
        
        return ApiResponse.success(jsonDecode(response.body));
      } else {
        // 失敗時も監査ログを記録
        await ModerationLogsService.logAdminAction(
          action: '${AdminActions.contentReview}_failed',
          targetType: contentType,
          targetId: contentId,
          reason: '操作失敗',
          metadata: {
            'operation_result': 'failed',
            'response_status': response.statusCode,
            'error_body': response.body,
          },
        );
        
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      // 例外発生時も監査ログを記録
      await ModerationLogsService.logAdminAction(
        action: '${AdminActions.contentReview}_error',
        targetType: contentType,
        targetId: contentId,
        reason: '例外発生',
        metadata: {
          'operation_result': 'exception',
          'error_message': e.toString(),
        },
      );
      
      return ApiResponse.error('Network error: $e');
    }
  }

  /// ユーザー検索（監査ログ付き）
  Future<ApiResponse<List<AdminUser>>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    try {
      // 監査ログを記録
      await ModerationLogsService.logAdminAction(
        action: 'user_search',
        targetType: AdminTargetTypes.user,
        targetId: 'search_query',
        reason: 'ユーザー検索実行',
        metadata: {
          'search_query': query,
          'search_limit': limit,
          'action_source': 'admin_interface',
        },
      );

      final uri = Uri.parse('$baseUrl/admin/users/search').replace(
        queryParameters: {
          'q': query,
          'limit': limit.toString(),
        },
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = (data['users'] as List)
            .map((user) => AdminUser.fromJson(user))
            .toList();

        // 検索結果も監査ログに記録
        await ModerationLogsService.logAdminAction(
          action: 'user_search_completed',
          targetType: AdminTargetTypes.user,
          targetId: 'search_result',
          reason: '検索完了',
          metadata: {
            'search_query': query,
            'results_count': users.length,
            'operation_result': 'success',
          },
        );

        return ApiResponse.success(users);
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// 通報されたコンテンツ一覧取得（監査ログ付き）
  Future<ApiResponse<List<Report>>> getReportedContents({
    int limit = 50,
    String status = 'pending',
  }) async {
    try {
      // 監査ログを記録
      await ModerationLogsService.logAdminAction(
        action: 'reports_view',
        targetType: AdminTargetTypes.report,
        targetId: 'report_list',
        reason: '通報一覧表示',
        metadata: {
          'view_limit': limit,
          'filter_status': status,
          'action_source': 'admin_interface',
        },
      );

      final uri = Uri.parse('$baseUrl/admin/contents/reported').replace(
        queryParameters: {
          'limit': limit.toString(),
          'status': status,
        },
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reports = (data['reports'] as List)
            .map((report) => Report.fromJson(report))
            .toList();
        return ApiResponse.success(reports);
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// ユーザーの停止・BAN（監査ログ付き）
  Future<ApiResponse<Map<String, dynamic>>> banUser({
    required String userId,
    required String reason,
    String? notes,
    int? durationDays,
  }) async {
    try {
      // 【重要】高リスク操作の監査ログを記録
      final auditLogged = await ModerationLogsService.logAdminAction(
        action: AdminActions.userBan,
        targetType: AdminTargetTypes.user,
        targetId: userId,
        reason: reason,
        notes: notes,
        metadata: {
          'ban_duration_days': durationDays,
          'action_source': 'admin_interface',
          'severity': 'HIGH',
        },
      );

      if (!auditLogged) {
        return ApiResponse.error('監査ログの記録に失敗しました。操作を中止します。');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/admin/users/ban'),
        headers: _headers,
        body: jsonEncode({
          'userId': userId,
          'reason': reason,
          if (notes != null) 'notes': notes,
          if (durationDays != null) 'durationDays': durationDays,
          'audit_logged': true,
        }),
      );

      if (response.statusCode == 200) {
        await ModerationLogsService.logAdminAction(
          action: '${AdminActions.userBan}_completed',
          targetType: AdminTargetTypes.user,
          targetId: userId,
          reason: 'BAN操作完了',
          metadata: {
            'operation_result': 'success',
            'response_status': response.statusCode,
          },
        );
        
        return ApiResponse.success(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// コンテンツの削除（監査ログ付き）
  Future<ApiResponse<Map<String, dynamic>>> deleteContent({
    required String contentId,
    required String contentType,
    required String reason,
    String? notes,
  }) async {
    try {
      // 【重要】高リスク操作の監査ログを記録
      final auditLogged = await ModerationLogsService.logAdminAction(
        action: AdminActions.contentDelete,
        targetType: contentType,
        targetId: contentId,
        reason: reason,
        notes: notes,
        metadata: {
          'action_source': 'admin_interface',
          'severity': 'HIGH',
        },
      );

      if (!auditLogged) {
        return ApiResponse.error('監査ログの記録に失敗しました。操作を中止します。');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/admin/contents/$contentId'),
        headers: _headers,
        body: jsonEncode({
          'contentType': contentType,
          'reason': reason,
          if (notes != null) 'notes': notes,
          'audit_logged': true,
        }),
      );

      if (response.statusCode == 200) {
        await ModerationLogsService.logAdminAction(
          action: '${AdminActions.contentDelete}_completed',
          targetType: contentType,
          targetId: contentId,
          reason: 'コンテンツ削除完了',
          metadata: {
            'operation_result': 'success',
            'response_status': response.statusCode,
          },
        );
        
        return ApiResponse.success(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// 監査ログの取得
  Future<ApiResponse<List<ModerationLog>>> getAuditLogs({
    String? adminUid,
    String? targetType,
    String? targetId,
    String? action,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    String? lastDocumentId,
  }) async {
    try {
      final logs = await ModerationLogsService.getModerationLogs(
        adminUid: adminUid,
        targetType: targetType,
        targetId: targetId,
        action: action,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        lastDocumentId: lastDocumentId,
      );

      return ApiResponse.success(logs);
    } catch (e) {
      return ApiResponse.error('監査ログの取得に失敗しました: $e');
    }
  }

  /// 管理者活動統計の取得
  Future<ApiResponse<Map<String, dynamic>>> getAdminStats({
    String? adminUid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final stats = await ModerationLogsService.getAdminActivityStats(
        adminUid: adminUid,
        startDate: startDate,
        endDate: endDate,
      );

      return ApiResponse.success(stats);
    } catch (e) {
      return ApiResponse.error('統計情報の取得に失敗しました: $e');
    }
  }

  /// 通報の解決（監査ログ付き）
  Future<ApiResponse<Map<String, dynamic>>> resolveReport({
    required String reportId,
    required String resolution,
    required String reason,
    String? notes,
  }) async {
    try {
      final auditLogged = await ModerationLogsService.logAdminAction(
        action: AdminActions.reportResolve,
        targetType: AdminTargetTypes.report,
        targetId: reportId,
        reason: reason,
        notes: notes,
        metadata: {
          'resolution_type': resolution,
          'action_source': 'admin_interface',
        },
      );

      if (!auditLogged) {
        return ApiResponse.error('監査ログの記録に失敗しました。操作を中止します。');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/admin/reports/$reportId/resolve'),
        headers: _headers,
        body: jsonEncode({
          'resolution': resolution,
          'reason': reason,
          if (notes != null) 'notes': notes,
          'audit_logged': true,
        }),
      );

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }
}

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;

  ApiResponse._({required this.success, this.data, this.error});

  factory ApiResponse.success(T data) => ApiResponse._(success: true, data: data);
  factory ApiResponse.error(String error) => ApiResponse._(success: false, error: error);
}

class AdminUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool disabled;
  final bool emailVerified;
  final String? creationTime;
  final String? lastSignInTime;

  AdminUser({
    required this.uid,
    this.email,
    this.displayName,
    required this.disabled,
    required this.emailVerified,
    this.creationTime,
    this.lastSignInTime,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      uid: json['uid'],
      email: json['email'],
      displayName: json['displayName'],
      disabled: json['disabled'] ?? false,
      emailVerified: json['emailVerified'] ?? false,
      creationTime: json['creationTime'],
      lastSignInTime: json['lastSignInTime'],
    );
  }
}

class Report {
  final String id;
  final String? contentId;
  final String? contentType;
  final String? reportedBy;
  final String? reason;
  final String? description;
  final String status;
  final String? createdAt;
  final String? reviewedBy;
  final String? reviewedAt;

  Report({
    required this.id,
    this.contentId,
    this.contentType,
    this.reportedBy,
    this.reason,
    this.description,
    required this.status,
    this.createdAt,
    this.reviewedBy,
    this.reviewedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'],
      contentId: json['contentId'],
      contentType: json['contentType'],
      reportedBy: json['reportedBy'],
      reason: json['reason'],
      description: json['description'],
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'],
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'],
    );
  }
}