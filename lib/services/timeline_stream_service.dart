import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/countdown.dart';
import 'mvp_analytics_client.dart';

class TimelineStreamService {
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
        final response = await http.get(
          Uri.parse('${MVPAnalyticsClient.baseUrl}/timeline/$targetUserId?limit=$limit'),
          headers: MVPAnalyticsClient.headers,
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final countdownsData = data['countdowns'] as List? ?? [];
          
          return countdownsData
              .map((json) => Countdown.fromJson(json))
              .toList();
        } else {
          print('TimelineStreamService - HTTP ${response.statusCode}: ${response.body}');
          return <Countdown>[];
        }
      } catch (e) {
        print('TimelineStreamService - Error getting personal timeline: $e');
        return <Countdown>[];
      }
    }).asyncMap((future) => future);
  }

  static Stream<List<Countdown>> getGlobalTimelineStream({
    int limit = 50,
  }) {
    return Stream.periodic(const Duration(seconds: 3), (count) async {
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
        } else {
          print('TimelineStreamService - HTTP ${response.statusCode}: ${response.body}');
          return <Countdown>[];
        }
      } catch (e) {
        print('TimelineStreamService - Error getting global timeline: $e');
        return <Countdown>[];
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
      final response = await http.get(
        Uri.parse('${MVPAnalyticsClient.baseUrl}/timeline/$targetUserId?limit=$limit'),
        headers: MVPAnalyticsClient.headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final countdownsData = data['countdowns'] as List? ?? [];
        
        return countdownsData
            .map((json) => Countdown.fromJson(json))
            .toList();
      } else {
        print('TimelineStreamService - HTTP ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      print('TimelineStreamService - Error getting timeline once: $e');
      return [];
    }
  }

  static Future<List<Countdown>> getGlobalTimelineOnce({
    int limit = 50,
  }) async {
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
      } else {
        print('TimelineStreamService - HTTP ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      print('TimelineStreamService - Error getting global timeline once: $e');
      return [];
    }
  }
}