// Fanout timeline service with Redis caching
// Implements efficient timeline distribution to followers

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'database_connection_manager.dart';
import 'polyglot_database_service.dart';
import '../config/database_config.dart';
import '../models/countdown.dart';

class FanoutTimelineService {
  static final DatabaseConnectionManager _connectionManager = DatabaseConnectionManager();
  static final PolyglotDatabaseService _dbService = PolyglotDatabaseService();
  
  // Timeline generation strategies
  static const int PUSH_THRESHOLD = 1000; // Max followers for push fanout
  static const int PULL_THRESHOLD = 10000; // Switch to pull for heavy users
  static const int TIMELINE_MAX_SIZE = 1000; // Max items in timeline cache
  static const int BATCH_SIZE = 100; // Fanout batch size
  
  // Initialize the fanout service
  static Future<void> initialize() async {
    await _startFanoutWorker();
  }
  
  // Create post and trigger fanout
  static Future<void> createPostWithFanout(Map<String, dynamic> postData) async {
    try {
      // 1. Create post in AlloyDB
      await _dbService.createPost(postData);
      
      // 2. Get creator's followers
      final creatorId = postData['creator_id'];
      final followers = await _getFollowersList(creatorId);
      
      // 3. Determine fanout strategy based on follower count
      final fanoutStrategy = _determineFanoutStrategy(followers.length);
      
      // 4. Execute fanout
      await _executeFanout(postData, followers, fanoutStrategy);
      
      // 5. Update global and category timelines
      await _updateGlobalTimelines(postData);
      
      print('FanoutTimelineService - Post created and fanout completed: ${postData['id']}');
      
    } catch (e) {
      print('FanoutTimelineService - Error creating post with fanout: $e');
      rethrow;
    }
  }
  
  // Determine fanout strategy based on follower count
  static FanoutStrategy _determineFanoutStrategy(int followerCount) {
    if (followerCount <= PUSH_THRESHOLD) {
      return FanoutStrategy.push; // Fanout to all followers immediately
    } else if (followerCount <= PULL_THRESHOLD) {
      return FanoutStrategy.hybrid; // Push to active users, pull for others
    } else {
      return FanoutStrategy.pull; // Pull-based for celebrity users
    }
  }
  
  // Execute fanout based on strategy
  static Future<void> _executeFanout(
    Map<String, dynamic> postData,
    List<String> followers,
    FanoutStrategy strategy,
  ) async {
    switch (strategy) {
      case FanoutStrategy.push:
        await _executePushFanout(postData, followers);
        break;
      case FanoutStrategy.hybrid:
        await _executeHybridFanout(postData, followers);
        break;
      case FanoutStrategy.pull:
        await _executePullFanout(postData);
        break;
    }
  }
  
  // Push fanout - distribute to all followers immediately
  static Future<void> _executePushFanout(
    Map<String, dynamic> postData,
    List<String> followers,
  ) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Create fanout jobs in batches
    for (int i = 0; i < followers.length; i += BATCH_SIZE) {
      final batch = followers.skip(i).take(BATCH_SIZE).toList();
      
      final fanoutJob = {
        'type': 'push_fanout',
        'postId': postData['id'],
        'creatorId': postData['creator_id'],
        'followers': batch,
        'postData': postData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'push',
      };
      
      await redis.send_object([
        'LPUSH',
        'fanout_queue',
        json.encode(fanoutJob),
      ]);
    }
    
    // Track fanout status
    await _trackFanoutStatus(postData['id'], followers.length, 'push');
  }
  
  // Hybrid fanout - push to active users, mark for pull for others
  static Future<void> _executeHybridFanout(
    Map<String, dynamic> postData,
    List<String> followers,
  ) async {
    // Identify active users (logged in within last 7 days)
    final activeUsers = await _getActiveUsers(followers);
    final inactiveUsers = followers.where((id) => !activeUsers.contains(id)).toList();
    
    // Push to active users
    if (activeUsers.isNotEmpty) {
      await _executePushFanout(postData, activeUsers);
    }
    
    // Mark for pull for inactive users
    if (inactiveUsers.isNotEmpty) {
      await _markForPullFanout(postData, inactiveUsers);
    }
    
    print('FanoutTimelineService - Hybrid fanout: ${activeUsers.length} push, ${inactiveUsers.length} pull');
  }
  
  // Pull fanout - store for on-demand timeline generation
  static Future<void> _executePullFanout(Map<String, dynamic> postData) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Add to creator's timeline cache
    await _addToUserTimeline(postData['creator_id'], postData);
    
    // Mark post as available for pull fanout
    await redis.send_object([
      'ZADD',
      'pull_fanout_posts',
      DateTime.now().millisecondsSinceEpoch,
      json.encode(postData),
    ]);
    
    // Set TTL for pull fanout posts (30 days)
    await redis.send_object(['EXPIRE', 'pull_fanout_posts', 2592000]);
    
    print('FanoutTimelineService - Pull fanout marked for post: ${postData['id']}');
  }
  
  // Mark posts for pull-based timeline generation
  static Future<void> _markForPullFanout(
    Map<String, dynamic> postData,
    List<String> userIds,
  ) async {
    final redis = _connectionManager.getRedisCommands();
    
    for (final userId in userIds) {
      await redis.send_object([
        'ZADD',
        'pull_timeline:$userId',
        DateTime.now().millisecondsSinceEpoch,
        postData['id'],
      ]);
      
      // Set TTL (7 days)
      await redis.send_object(['EXPIRE', 'pull_timeline:$userId', 604800]);
    }
  }
  
  // Add post to user's timeline cache
  static Future<void> _addToUserTimeline(String userId, Map<String, dynamic> postData) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Create timeline item with score (timestamp for ordering)
    final score = DateTime.now().millisecondsSinceEpoch;
    final timelineItem = '${postData['id']}:${postData['category']}:${postData['event_date']}:$score';
    
    // Add to timeline sorted set
    await redis.send_object([
      'ZADD',
      'timeline:$userId',
      score,
      timelineItem,
    ]);
    
    // Trim timeline to max size
    await redis.send_object([
      'ZREMRANGEBYRANK',
      'timeline:$userId',
      0,
      -(TIMELINE_MAX_SIZE + 1),
    ]);
    
    // Set TTL
    await redis.send_object([
      'EXPIRE',
      'timeline:$userId',
      DatabaseConfig.cacheTtl['user_timeline']!,
    ]);
    
    // Update timeline metadata
    await _updateTimelineMetadata(userId);
  }
  
  // Update timeline metadata
  static Future<void> _updateTimelineMetadata(String userId) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Get timeline size
    final timelineSize = await redis.send_object(['ZCARD', 'timeline:$userId']);
    
    // Update metadata
    await redis.send_object(['HSET', 'timeline:meta:$userId', 'last_updated', DateTime.now().millisecondsSinceEpoch]);
    await redis.send_object(['HSET', 'timeline:meta:$userId', 'total_items', timelineSize ?? 0]);
    await redis.send_object(['HSET', 'timeline:meta:$userId', 'timeline_version', 2]);
    
    // Set TTL for metadata
    await redis.send_object([
      'EXPIRE',
      'timeline:meta:$userId',
      DatabaseConfig.cacheTtl['user_timeline']!,
    ]);
  }
  
  // Update global and category timelines
  static Future<void> _updateGlobalTimelines(Map<String, dynamic> postData) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Calculate trend score
    final trendScore = _calculateTrendScore(postData);
    final timelineItem = '${postData['id']}:${postData['category']}:${postData['created_at']}';
    
    // Update global timeline
    await redis.send_object([
      'ZADD',
      'global_timeline',
      trendScore,
      timelineItem,
    ]);
    
    // Update category timeline
    await redis.send_object([
      'ZADD',
      'timeline:category:${postData['category']}',
      trendScore,
      timelineItem,
    ]);
    
    // Trim global timeline
    await redis.send_object([
      'ZREMRANGEBYRANK',
      'global_timeline',
      0,
      -(TIMELINE_MAX_SIZE + 1),
    ]);
    
    // Set TTLs
    await redis.send_object(['EXPIRE', 'global_timeline', DatabaseConfig.cacheTtl['global_timeline']!]);
    await redis.send_object(['EXPIRE', 'timeline:category:${postData['category']}', DatabaseConfig.cacheTtl['category_timeline']!]);
  }
  
  // Calculate trend score for timeline ranking
  static double _calculateTrendScore(Map<String, dynamic> postData) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = DateTime.parse(postData['created_at']).millisecondsSinceEpoch;
    final ageHours = (now - createdAt) / (1000 * 60 * 60);
    
    // Engagement metrics
    final likes = postData['likes_count'] ?? 0;
    final comments = postData['comments_count'] ?? 0;
    final views = postData['views_count'] ?? 0;
    
    // Calculate score with time decay
    final engagementScore = (likes * 3) + (comments * 5) + (views * 1);
    final timeDecay = pow(0.8, ageHours / 24); // Decay over days
    
    return engagementScore * timeDecay;
  }
  
  // Get user's timeline with pull-based generation if needed
  static Future<List<Map<String, dynamic>>> getUserTimeline(
    String userId, {
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    try {
      // Try cache first if not forcing refresh
      if (!forceRefresh) {
        final cached = await _getTimelineFromCache(userId, limit);
        if (cached.isNotEmpty) {
          return cached;
        }
      }
      
      // Generate timeline using pull strategy
      return await _generatePullTimeline(userId, limit);
      
    } catch (e) {
      print('FanoutTimelineService - Error getting user timeline: $e');
      return [];
    }
  }
  
  // Get timeline from Redis cache
  static Future<List<Map<String, dynamic>>> _getTimelineFromCache(String userId, int limit) async {
    final redis = _connectionManager.getRedisCommands();
    
    final timelineData = await redis.send_object([
      'ZREVRANGE',
      'timeline:$userId',
      0,
      limit - 1,
      'WITHSCORES',
    ]);
    
    if (timelineData != null) {
      final items = List.from(timelineData);
      final timeline = <Map<String, dynamic>>[];
      
      for (int i = 0; i < items.length; i += 2) {
        final parts = items[i].toString().split(':');
        if (parts.length >= 4) {
          timeline.add({
            'postId': parts[0],
            'category': parts[1],
            'eventDate': parts[2],
            'score': double.parse(items[i + 1].toString()),
            'timestamp': int.parse(parts[3]),
          });
        }
      }
      
      return timeline;
    }
    
    return [];
  }
  
  // Generate timeline using pull strategy
  static Future<List<Map<String, dynamic>>> _generatePullTimeline(String userId, int limit) async {
    // Get user's following list
    final following = await _getFollowingList(userId);
    
    if (following.isEmpty) {
      return [];
    }
    
    // Get recent posts from followed users
    final timeline = await _getPostsFromFollowing(following, limit * 2); // Get more for filtering
    
    // Sort by relevance/recency and limit
    timeline.sort((a, b) => (b['score'] ?? 0.0).compareTo(a['score'] ?? 0.0));
    final result = timeline.take(limit).toList();
    
    // Cache the generated timeline
    await _cacheGeneratedTimeline(userId, result);
    
    return result;
  }
  
  // Get posts from users that the current user is following
  static Future<List<Map<String, dynamic>>> _getPostsFromFollowing(
    List<String> following,
    int limit,
  ) async {
    final posts = <Map<String, dynamic>>[];
    
    // Query posts from AlloyDB
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      final placeholders = following.map((_, index) => '@userId$index').join(', ');
      final substitutionValues = <String, dynamic>{};
      
      for (int i = 0; i < following.length; i++) {
        substitutionValues['userId$i'] = following[i];
      }
      
      final results = await connection.query('''
        SELECT p.*, u.username as creator_username, u.display_name as creator_display_name
        FROM posts p
        JOIN users u ON p.creator_id = u.id
        WHERE u.firebase_uid IN ($placeholders)
        AND p.status = 'visible'
        AND p.created_at > NOW() - INTERVAL '7 days'
        ORDER BY p.created_at DESC
        LIMIT @limit
      ''', substitutionValues: {
        ...substitutionValues,
        'limit': limit,
      });
      
      for (final row in results) {
        final post = row.toColumnMap();
        post['score'] = _calculateTrendScore(post);
        posts.add(post);
      }
      
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
    
    return posts;
  }
  
  // Cache generated timeline
  static Future<void> _cacheGeneratedTimeline(String userId, List<Map<String, dynamic>> timeline) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Clear existing timeline
    await redis.send_object(['DEL', 'timeline:$userId']);
    
    // Add items to timeline
    for (final item in timeline) {
      final score = item['score'] ?? DateTime.now().millisecondsSinceEpoch;
      final timelineItem = '${item['id']}:${item['category']}:${item['event_date']}:$score';
      
      await redis.send_object([
        'ZADD',
        'timeline:$userId',
        score,
        timelineItem,
      ]);
    }
    
    // Set TTL
    await redis.send_object([
      'EXPIRE',
      'timeline:$userId',
      DatabaseConfig.cacheTtl['user_timeline']!,
    ]);
    
    // Update metadata
    await _updateTimelineMetadata(userId);
  }
  
  // Helper methods
  static Future<List<String>> _getFollowersList(String userId) async {
    return await _dbService.executeOperation<List<String>>(
      'follows',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.redis:
            final redis = _connectionManager.getRedisCommands();
            final followers = await redis.send_object(['SMEMBERS', 'followers:$userId']);
            return followers != null ? List<String>.from(followers) : [];
          case DatabaseType.alloydb:
            final connection = await _connectionManager.getAlloyDbConnection();
            try {
              final results = await connection.query('''
                SELECT u.firebase_uid 
                FROM follows f
                JOIN users u ON f.follower_id = u.id
                JOIN users target ON f.following_id = target.id
                WHERE target.firebase_uid = @userId
              ''', substitutionValues: {'userId': userId});
              return results.map((row) => row[0] as String).toList();
            } finally {
              _connectionManager.returnAlloyDbConnection(connection);
            }
          default:
            return [];
        }
      },
      useCache: true,
    );
  }
  
  static Future<List<String>> _getFollowingList(String userId) async {
    return await _dbService.executeOperation<List<String>>(
      'follows',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.redis:
            final redis = _connectionManager.getRedisCommands();
            final following = await redis.send_object(['SMEMBERS', 'following:$userId']);
            return following != null ? List<String>.from(following) : [];
          case DatabaseType.alloydb:
            final connection = await _connectionManager.getAlloyDbConnection();
            try {
              final results = await connection.query('''
                SELECT target.firebase_uid 
                FROM follows f
                JOIN users u ON f.follower_id = u.id
                JOIN users target ON f.following_id = target.id
                WHERE u.firebase_uid = @userId
              ''', substitutionValues: {'userId': userId});
              return results.map((row) => row[0] as String).toList();
            } finally {
              _connectionManager.returnAlloyDbConnection(connection);
            }
          default:
            return [];
        }
      },
      useCache: true,
    );
  }
  
  static Future<List<String>> _getActiveUsers(List<String> userIds) async {
    // For simplicity, consider users active if they have cached data
    final redis = _connectionManager.getRedisCommands();
    final activeUsers = <String>[];
    
    for (final userId in userIds) {
      final exists = await redis.send_object(['EXISTS', 'user_session:$userId']);
      if (exists == 1) {
        activeUsers.add(userId);
      }
    }
    
    return activeUsers;
  }
  
  static Future<void> _trackFanoutStatus(String postId, int totalFollowers, String strategy) async {
    final redis = _connectionManager.getRedisCommands();
    
    await redis.send_object(['HSET', 'fanout_status:$postId', 'status', 'processing']);
    await redis.send_object(['HSET', 'fanout_status:$postId', 'total_followers', totalFollowers]);
    await redis.send_object(['HSET', 'fanout_status:$postId', 'processed_followers', 0]);
    await redis.send_object(['HSET', 'fanout_status:$postId', 'strategy', strategy]);
    await redis.send_object(['HSET', 'fanout_status:$postId', 'started_at', DateTime.now().millisecondsSinceEpoch]);
    
    // Set TTL (24 hours)
    await redis.send_object(['EXPIRE', 'fanout_status:$postId', 86400]);
  }
  
  // Fanout worker to process queued jobs
  static Future<void> _startFanoutWorker() async {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _processFanoutQueue();
    });
  }
  
  static Future<void> _processFanoutQueue() async {
    try {
      final redis = _connectionManager.getRedisCommands();
      
      // Get job from queue
      final result = await redis.send_object(['BRPOP', 'fanout_queue', 1]);
      
      if (result != null && result is List && result.length >= 2) {
        final jobData = json.decode(result[1]);
        await _processFanoutJob(jobData);
      }
    } catch (e) {
      print('FanoutTimelineService - Error processing fanout queue: $e');
    }
  }
  
  static Future<void> _processFanoutJob(Map<String, dynamic> job) async {
    try {
      final followers = List<String>.from(job['followers']);
      final postData = Map<String, dynamic>.from(job['postData']);
      
      // Add post to each follower's timeline
      for (final followerId in followers) {
        await _addToUserTimeline(followerId, postData);
      }
      
      // Update fanout status
      await _updateFanoutProgress(job['postId'], followers.length);
      
    } catch (e) {
      print('FanoutTimelineService - Error processing fanout job: $e');
    }
  }
  
  static Future<void> _updateFanoutProgress(String postId, int processedCount) async {
    final redis = _connectionManager.getRedisCommands();
    
    await redis.send_object(['HINCRBY', 'fanout_status:$postId', 'processed_followers', processedCount]);
    
    // Check if fanout is complete
    final status = await redis.send_object(['HGETALL', 'fanout_status:$postId']);
    if (status != null) {
      final statusMap = <String, String>{};
      final statusList = List.from(status);
      
      for (int i = 0; i < statusList.length; i += 2) {
        statusMap[statusList[i].toString()] = statusList[i + 1].toString();
      }
      
      final total = int.parse(statusMap['total_followers'] ?? '0');
      final processed = int.parse(statusMap['processed_followers'] ?? '0');
      
      if (processed >= total) {
        await redis.send_object(['HSET', 'fanout_status:$postId', 'status', 'completed']);
        await redis.send_object(['HSET', 'fanout_status:$postId', 'completed_at', DateTime.now().millisecondsSinceEpoch]);
      }
    }
  }
  
  // Get fanout status for a post
  static Future<Map<String, dynamic>> getFanoutStatus(String postId) async {
    final redis = _connectionManager.getRedisCommands();
    
    final status = await redis.send_object(['HGETALL', 'fanout_status:$postId']);
    
    if (status != null) {
      final statusMap = <String, dynamic>{};
      final statusList = List.from(status);
      
      for (int i = 0; i < statusList.length; i += 2) {
        statusMap[statusList[i].toString()] = statusList[i + 1].toString();
      }
      
      return statusMap;
    }
    
    return {'status': 'not_found'};
  }
}

// Fanout strategy enumeration
enum FanoutStrategy {
  push,   // Push to all followers immediately
  hybrid, // Push to active users, pull for inactive
  pull,   // Pull-based timeline generation
}