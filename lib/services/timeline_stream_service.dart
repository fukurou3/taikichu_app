import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import 'simple_firestore_service.dart';

class TimelineStreamService {
  static Stream<List<Countdown>> getPersonalTimelineStream({
    String? userId,
    int limit = 50,
  }) {
    final targetUserId = userId ?? FirebaseAuth.instance.currentUser?.uid;
    
    if (targetUserId == null) {
      return Stream.value([]);
    }

    // Use SimpleFirestoreService for real-time timeline updates
    return SimpleFirestoreService.getTimelineStream(targetUserId, limit: limit);
  }

  static Stream<List<Countdown>> getGlobalTimelineStream({
    int limit = 50,
  }) {
    // Global timeline using periodic updates (simplified approach)
    return Stream.periodic(const Duration(seconds: 5), (count) async {
      return await SimpleFirestoreService.searchPosts('', limit: limit);
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

    // Simplified: direct call to SimpleFirestoreService
    return await SimpleFirestoreService.getTimeline(targetUserId, limit: limit);
  }

  static Future<List<Countdown>> getGlobalTimelineOnce({
    int limit = 50,
  }) async {
    // Simplified: use search with empty query to get recent posts
    return await SimpleFirestoreService.searchPosts('', limit: limit);
  }

}