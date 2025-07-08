import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/countdown.dart';
import 'mvp_analytics_client.dart';
import 'polyglot_database_service.dart';

class TimelineStreamService {
  static final PolyglotDatabaseService _dbService = PolyglotDatabaseService();
  static Stream<List<Countdown>> getPersonalTimelineStream({
    String? userId,
    int limit = 50,
  }) {
    final targetUserId = userId ?? FirebaseAuth.instance.currentUser?.uid;
    
    if (targetUserId == null) {
      return Stream.value([]);
    }

    return Stream.periodic(const Duration(seconds: 3), (count) async {
      try {
        // Use polyglot database service with caching and fallback
        final timelineData = await _dbService.getUserTimeline(targetUserId, limit: limit);
        
        // Convert to Countdown objects
        final countdowns = timelineData
            .map((data) => _mapToCountdown(data))
            .where((countdown) => countdown != null)
            .cast<Countdown>()
            .toList();
            
        return countdowns;
      } catch (e) {
        print('TimelineStreamService - Error getting personal timeline: $e');
        // Fallback to direct analytics service
        return await _getPersonalTimelineFallback(targetUserId, limit);
      }
    }).asyncMap((future) => future);
  }

  static Stream<List<Countdown>> getGlobalTimelineStream({
    int limit = 50,
  }) {
    return Stream.periodic(const Duration(seconds: 3), (count) async {
      try {
        // Use polyglot database service for global timeline
        final timelineData = await _dbService.getPostsByCategory('global', limit: limit);
        
        // Convert to Countdown objects
        final countdowns = timelineData
            .map((data) => _mapToCountdown(data))
            .where((countdown) => countdown != null)
            .cast<Countdown>()
            .toList();
            
        return countdowns;
      } catch (e) {
        print('TimelineStreamService - Error getting global timeline: $e');
        // Fallback to direct analytics service
        return await _getGlobalTimelineFallback(limit);
      }
    }).asyncMap((future) => future);
  }

  static Stream<List<Countdown>> getBatchedTimelineStream({
    String? userId,
    int limit = 50,
    Duration batchInterval = const Duration(seconds: 3),
  }) {
    return getPersonalTimelineStream(
      userId: userId,
      limit: limit,
    ).distinct((previous, current) {
      // データが変わった場合のみ更新を通知
      if (previous.length != current.length) return false;
      
      for (int i = 0; i < previous.length; i++) {
        if (previous[i].id != current[i].id) return false;
      }
      
      return true;
    });
  }

  static Future<List<Countdown>> getTimelineOnce({
    String? userId,
    int limit = 50,
  }) async {
    final targetUserId = userId ?? FirebaseAuth.instance.currentUser?.uid;
    
    if (targetUserId == null) {
      return [];
    }

    try {
      // Use polyglot database service with caching
      final timelineData = await _dbService.getUserTimeline(targetUserId, limit: limit);
      
      // Convert to Countdown objects
      final countdowns = timelineData
          .map((data) => _mapToCountdown(data))
          .where((countdown) => countdown != null)
          .cast<Countdown>()
          .toList();
          
      return countdowns;
    } catch (e) {
      print('TimelineStreamService - Error getting timeline once: $e');
      // Fallback to direct analytics service
      return await _getPersonalTimelineFallback(targetUserId, limit);
    }
  }

  static Future<List<Countdown>> getGlobalTimelineOnce({
    int limit = 50,
  }) async {
    try {
      // Use polyglot database service for global timeline
      final timelineData = await _dbService.getPostsByCategory('global', limit: limit);
      
      // Convert to Countdown objects
      final countdowns = timelineData
          .map((data) => _mapToCountdown(data))
          .where((countdown) => countdown != null)
          .cast<Countdown>()
          .toList();
          
      return countdowns;
    } catch (e) {
      print('TimelineStreamService - Error getting global timeline once: $e');
      // Fallback to direct analytics service
      return await _getGlobalTimelineFallback(limit);
    }
  }

  // Helper method to map database data to Countdown objects
  static Countdown? _mapToCountdown(Map<String, dynamic> data) {
    try {
      return Countdown(
        id: data['id'] ?? data['postId'] ?? '',
        eventName: data['eventName'] ?? data['event_name'] ?? '',
        description: data['description'] ?? '',
        eventDate: data['eventDate'] != null 
            ? DateTime.parse(data['eventDate']) 
            : data['event_date'] != null
                ? DateTime.parse(data['event_date'])
                : DateTime.now(),
        category: data['category'] ?? '',
        creatorId: data['creatorId'] ?? data['creator_id'] ?? '',
        imageUrl: data['imageUrl'] ?? data['image_url'],
        participantsCount: data['participantsCount'] ?? data['participants_count'] ?? 0,
        likesCount: data['likesCount'] ?? data['likes_count'] ?? 0,
        commentsCount: data['commentsCount'] ?? data['comments_count'] ?? 0,
        viewsCount: data['viewsCount'] ?? data['views_count'] ?? 0,
        recentLikesCount: data['recentLikesCount'] ?? data['recent_likes_count'] ?? 0,
        recentCommentsCount: data['recentCommentsCount'] ?? data['recent_comments_count'] ?? 0,
        recentViewsCount: data['recentViewsCount'] ?? data['recent_views_count'] ?? 0,
        status: data['status'] ?? 'visible',
        hashtags: data['hashtags'] != null 
            ? List<String>.from(data['hashtags'])
            : [],
      );
    } catch (e) {
      print('Error mapping data to Countdown: $e');
      return null;
    }
  }

  // Fallback methods for direct analytics service access
  static Future<List<Countdown>> _getPersonalTimelineFallback(String userId, int limit) async {
    try {
      final response = await http.get(
        Uri.parse('${MVPAnalyticsClient.baseUrl}/timeline/$userId?limit=$limit'),
        headers: MVPAnalyticsClient.headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final countdownsData = data['countdowns'] as List? ?? [];
        
        return countdownsData
            .map((json) => Countdown.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      print('Fallback timeline request failed: $e');
      return [];
    }
  }

  static Future<List<Countdown>> _getGlobalTimelineFallback(int limit) async {
    try {
      final response = await http.get(
        Uri.parse('${MVPAnalyticsClient.baseUrl}/global-timeline?limit=$limit'),
        headers: MVPAnalyticsClient.headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final countdownsData = data['countdowns'] as List? ?? [];
        
        return countdownsData
            .map((json) => Countdown.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      print('Fallback global timeline request failed: $e');
      return [];
    }
  }
}