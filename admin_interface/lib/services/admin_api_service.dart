import 'dart:convert';
import 'package:http/http.dart' as http;

class AdminApiService {
  // Cloud Run analytics service URL
  static const String baseUrl = 'https://analytics-service-694414843228.asia-northeast1.run.app';
  
  final String? _authToken;
  
  AdminApiService(this._authToken);
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// コンテンツのモデレーション
  Future<ApiResponse<Map<String, dynamic>>> moderateContent({
    required String contentId,
    required String contentType,
    required String newStatus,
    required String reason,
    String? notes,
  }) async {
    try {
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

  /// ユーザー検索
  Future<ApiResponse<List<AdminUser>>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    try {
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

  /// 通報されたコンテンツ一覧取得
  Future<ApiResponse<List<Report>>> getReportedContents({
    int limit = 50,
    String status = 'pending',
  }) async {
    try {
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