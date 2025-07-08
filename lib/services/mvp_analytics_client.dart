// MVP Analytics Client for Phase0 v2.1
// Simplified version without Cloud Functions dependency

class TrendRankingItem {
  final String id;
  final String title;
  final int count;
  final DateTime timestamp;

  TrendRankingItem({
    required this.id,
    required this.title,
    required this.count,
    required this.timestamp,
  });

  factory TrendRankingItem.fromMap(Map<String, dynamic> map) {
    return TrendRankingItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      count: map['count'] ?? 0,
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

class MVPAnalyticsClient {
  // Simplified static methods for Phase0
  
  static Future<List<TrendRankingItem>> getTrendRanking({
    int limit = 10,
    int offset = 0,
  }) async {
    // Phase0: Return mock data instead of Cloud Functions call
    await Future.delayed(Duration(milliseconds: 500)); // Simulate network delay
    
    return List.generate(limit, (index) {
      return TrendRankingItem(
        id: 'trend_${offset + index}',
        title: 'Phase0 Trend ${offset + index + 1}',
        count: 100 - (offset + index),
        timestamp: DateTime.now().subtract(Duration(hours: index)),
      );
    });
  }

  static Future<List<Map<String, dynamic>>> getCountdowns({
    int limit = 20,
    int offset = 0,
    String? query,
  }) async {
    // Phase0: Return mock data
    await Future.delayed(Duration(milliseconds: 300));
    
    return List.generate(limit, (index) {
      final id = 'countdown_${offset + index}';
      return {
        'id': id,
        'title': query != null ? 'Search: $query ${index + 1}' : 'Phase0 Countdown ${offset + index + 1}',
        'description': 'Phase0 description for countdown ${offset + index + 1}',
        'targetDate': DateTime.now().add(Duration(days: index + 1)).toIso8601String(),
        'userId': 'user_${index % 5}',
        'userName': 'User ${index % 5 + 1}',
        'likesCount': (index * 3) % 50,
        'commentsCount': (index * 2) % 20,
        'createdAt': DateTime.now().subtract(Duration(hours: index)).toIso8601String(),
      };
    });
  }

  static Future<List<Map<String, dynamic>>> getComments(
    String countdownId, {
    int limit = 10,
    int offset = 0,
  }) async {
    // Phase0: Return mock comments
    await Future.delayed(Duration(milliseconds: 200));
    
    return List.generate(limit, (index) {
      return {
        'id': 'comment_${countdownId}_${offset + index}',
        'text': 'Phase0 comment ${offset + index + 1} for $countdownId',
        'userId': 'user_${index % 3}',
        'userName': 'Commenter ${index % 3 + 1}',
        'createdAt': DateTime.now().subtract(Duration(minutes: index * 10)).toIso8601String(),
        'countdownId': countdownId,
      };
    });
  }

  // Additional helper methods for Phase0
  static Future<Map<String, dynamic>> getCountdownById(String id) async {
    await Future.delayed(Duration(milliseconds: 200));
    
    return {
      'id': id,
      'title': 'Phase0 Countdown Detail',
      'description': 'Detailed description for $id',
      'targetDate': DateTime.now().add(Duration(days: 7)).toIso8601String(),
      'userId': 'user_1',
      'userName': 'Phase0 User',
      'likesCount': 42,
      'commentsCount': 12,
      'createdAt': DateTime.now().subtract(Duration(hours: 2)).toIso8601String(),
    };
  }

  static Future<bool> likeCountdown(String countdownId) async {
    await Future.delayed(Duration(milliseconds: 100));
    return true; // Phase0: Always succeed
  }

  static Future<bool> unlikeCountdown(String countdownId) async {
    await Future.delayed(Duration(milliseconds: 100));
    return true; // Phase0: Always succeed
  }

  static Future<Map<String, dynamic>> addComment(
    String countdownId,
    String text,
  ) async {
    await Future.delayed(Duration(milliseconds: 300));
    
    return {
      'id': 'new_comment_${DateTime.now().millisecondsSinceEpoch}',
      'text': text,
      'userId': 'current_user',
      'userName': 'Current User',
      'createdAt': DateTime.now().toIso8601String(),
      'countdownId': countdownId,
    };
  }
}