import 'dart:convert';
import 'package:http/http.dart' as http;
// import '../../../lib/services/moderation_logs_service.dart'; // 🛡️ バックエンド主導に移行
// import '../../../lib/services/admin_authorization_service.dart'; // 🛡️ バックエンド主導に移行

// 🛡️ バックエンド主導で監査ログ記録を実現
// ModerationLogクラスは監査ログ表示用のみ
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
      id: json['id'],
      action: json['action'],
      targetType: json['targetType'],
      targetId: json['targetId'],
      reason: json['reason'],
      adminUid: json['adminUid'],
      adminEmail: json['adminEmail'],
      timestamp: DateTime.parse(json['timestamp']),
      ipAddress: json['ipAddress'],
      userAgent: json['userAgent'],
      notes: json['notes'],
      metadata: json['metadata'],
      previousState: json['previousState'],
      newState: json['newState'],
      severity: json['severity'],
      requiresApproval: json['requiresApproval'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'adminUid': adminUid,
      'adminEmail': adminEmail,
      'timestamp': timestamp.toIso8601String(),
      'ipAddress': ipAddress,
      'userAgent': userAgent,
      'notes': notes,
      'metadata': metadata,
      'previousState': previousState,
      'newState': newState,
      'severity': severity,
      'requiresApproval': requiresApproval,
    };
  }
}

class AdminApiService {
  // Cloud Run analytics service URL
  static const String baseUrl = 'https://analytics-service-694414843228.asia-northeast1.run.app';
  
  final String? _authToken;
  
  AdminApiService(this._authToken);
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// コンテンツのモデレーション（バックエンド主導）
  Future<ApiResponse<Map<String, dynamic>>> moderateContent({
    required String contentId,
    required String contentType,
    required String newStatus,
    required String reason,
    String? notes,
  }) async {
    try {
      // 🛡️ バックエンドが全ての認証・認可・監査ログを処理
      final response = await http.post(
        Uri.parse('$baseUrl/admin/contents/moderate'),
        headers: _headers,
        body: jsonEncode({
          'contentId': contentId,
          'contentType': contentType,
          'newStatus': newStatus,
          'reason': reason,
          if (notes != null) 'notes': notes,
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

  /// ユーザー検索（バックエンド主導）
  Future<ApiResponse<List<AdminUser>>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    try {
      // 🛡️ バックエンドが監査ログを自動記録
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
        return ApiResponse.success(users);
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// 通報されたコンテンツ一覧取得（バックエンド主導）
  Future<ApiResponse<List<Report>>> getReportedContents({
    int limit = 50,
    String status = 'pending',
  }) async {
    try {
      // 🛡️ バックエンドが監査ログを自動記録
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

  /// ユーザーの停止・BAN（バックエンド主導）
  Future<ApiResponse<Map<String, dynamic>>> banUser({
    required String userId,
    required String reason,
    String? notes,
    int? durationDays,
  }) async {
    try {
      // 🛡️ バックエンドが全ての認証・認可・監査ログを処理
      final response = await http.post(
        Uri.parse('$baseUrl/admin/users/ban'),
        headers: _headers,
        body: jsonEncode({
          'userId': userId,
          'reason': reason,
          if (notes != null) 'notes': notes,
          if (durationDays != null) 'durationDays': durationDays,
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

  /// コンテンツの削除（バックエンド主導）
  Future<ApiResponse<Map<String, dynamic>>> deleteContent({
    required String contentId,
    required String contentType,
    required String reason,
    String? notes,
  }) async {
    try {
      // 🛡️ バックエンドが全ての認証・認可・監査ログを処理
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/contents/$contentId'),
        headers: _headers,
        body: jsonEncode({
          'contentType': contentType,
          'reason': reason,
          if (notes != null) 'notes': notes,
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

  /// 監査ログの取得（バックエンド主導）
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
      // 🛡️ バックエンドから監査ログを取得
      final uri = Uri.parse('$baseUrl/admin/logs').replace(
        queryParameters: {
          if (adminUid != null) 'adminUid': adminUid,
          if (targetType != null) 'targetType': targetType,
          if (targetId != null) 'targetId': targetId,
          if (action != null) 'action': action,
          if (startDate != null) 'startDate': startDate.toIso8601String(),
          if (endDate != null) 'endDate': endDate.toIso8601String(),
          'limit': limit.toString(),
          if (lastDocumentId != null) 'lastDocumentId': lastDocumentId,
        },
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final logs = (data['logs'] as List)
            .map((log) => ModerationLog.fromJson(log))
            .toList();
        return ApiResponse.success(logs);
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('監査ログの取得に失敗しました: $e');
    }
  }

  /// 管理者活動統計の取得（バックエンド主導）
  Future<ApiResponse<Map<String, dynamic>>> getAdminStats({
    String? adminUid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // 🛡️ バックエンドから管理者統計を取得
      final uri = Uri.parse('$baseUrl/admin/activity-stats').replace(
        queryParameters: {
          if (adminUid != null) 'adminUid': adminUid,
          if (startDate != null) 'startDate': startDate.toIso8601String(),
          if (endDate != null) 'endDate': endDate.toIso8601String(),
        },
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(data);
      } else {
        final error = jsonDecode(response.body);
        return ApiResponse.error(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      return ApiResponse.error('統計情報の取得に失敗しました: $e');
    }
  }

  /// 通報の解決（バックエンド主導）
  Future<ApiResponse<Map<String, dynamic>>> resolveReport({
    required String reportId,
    required String resolution,
    required String reason,
    String? notes,
  }) async {
    try {
      // 🛡️ バックエンドが全ての認証・認可・監査ログを処理
      final response = await http.post(
        Uri.parse('$baseUrl/admin/reports/$reportId/resolve'),
        headers: _headers,
        body: jsonEncode({
          'resolution': resolution,
          'reason': reason,
          if (notes != null) 'notes': notes,
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