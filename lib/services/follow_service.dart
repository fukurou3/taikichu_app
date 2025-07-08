import 'package:firebase_auth/firebase_auth.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';
import 'polyglot_database_service.dart';

class FollowService {
  static final PolyglotDatabaseService _dbService = PolyglotDatabaseService();
  static Future<void> toggleFollow(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // Check current follow status using polyglot database
      final isCurrentlyFollowing = await isFollowing(targetUserId);
      
      // Use polyglot database service for follow operations
      if (isCurrentlyFollowing) {
        await _unfollowUser(user.uid, targetUserId);
      } else {
        await _followUser(user.uid, targetUserId);
      }

      // Also send to unified analytics pipeline for event tracking
      await UnifiedAnalyticsService.sendEvent(
        type: 'follow_toggle',
        countdownId: targetUserId,
        eventData: {
          'action': isCurrentlyFollowing ? 'unfollow' : 'follow',
          'targetUserId': targetUserId,
          'currentUserId': user.uid,
        },
      );

      print('FollowService - Toggle follow completed for user: $targetUserId');
    } catch (e) {
      print('FollowService - Error toggling follow: $e');
      rethrow;
    }
  }

  static Future<bool> isFollowing(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      // Use polyglot database service to check follow status with caching
      final followData = await _dbService.executeOperation<bool>(
        'follows',
        (dbType) async {
          switch (dbType) {
            case DatabaseType.redis:
              return await _checkFollowStatusFromRedis(user.uid, targetUserId);
            case DatabaseType.alloydb:
              return await _checkFollowStatusFromAlloyDb(user.uid, targetUserId);
            default:
              // Fallback to analytics service
              final response = await MVPAnalyticsClient.getUserState(user.uid, targetUserId);
              return response['is_following'] ?? false;
          }
        },
        useCache: true,
      );
      
      return followData;
    } catch (e) {
      print('FollowService - Error checking follow state: $e');
      // Fallback to analytics service
      try {
        final response = await MVPAnalyticsClient.getUserState(user.uid, targetUserId);
        return response['is_following'] ?? false;
      } catch (fallbackError) {
        print('FollowService - Fallback also failed: $fallbackError');
        return false;
      }
    }
  }

  static Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      // Use polyglot database service with caching for follow counts
      final counts = await _dbService.executeOperation<Map<String, int>>(
        'follows',
        (dbType) async {
          switch (dbType) {
            case DatabaseType.redis:
              return await _getFollowCountsFromRedis(userId);
            case DatabaseType.alloydb:
              return await _getFollowCountsFromAlloyDb(userId);
            default:
              // Fallback to analytics service
              final response = await MVPAnalyticsClient.getUserFollows(userId);
              return Map<String, int>.from(response['follow_counts'] ?? {'following': 0, 'followers': 0});
          }
        },
        useCache: true,
      );
      
      return counts;
    } catch (e) {
      print('FollowService - Error getting follow counts: $e');
      // Fallback to analytics service
      try {
        final response = await MVPAnalyticsClient.getUserFollows(userId);
        return Map<String, int>.from(response['follow_counts'] ?? {'following': 0, 'followers': 0});
      } catch (fallbackError) {
        return {'following': 0, 'followers': 0};
      }
    }
  }

  static Future<List<String>> getFollowers(String userId) async {
    try {
      // Use polyglot database service for follower lists
      final followers = await _dbService.executeOperation<List<String>>(
        'follows',
        (dbType) async {
          switch (dbType) {
            case DatabaseType.redis:
              return await _getFollowersFromRedis(userId);
            case DatabaseType.alloydb:
              return await _getFollowersFromAlloyDb(userId);
            default:
              // Fallback to analytics service
              final response = await MVPAnalyticsClient.getFollowers(userId);
              return List<String>.from(response['followers'] ?? []);
          }
        },
        useCache: true,
      );
      
      return followers;
    } catch (e) {
      print('FollowService - Error getting followers: $e');
      // Fallback to analytics service
      try {
        final response = await MVPAnalyticsClient.getFollowers(userId);
        return List<String>.from(response['followers'] ?? []);
      } catch (fallbackError) {
        return [];
      }
    }
  }

  // Private helper methods for database operations
  static Future<void> _followUser(String followerId, String followingId) async {
    await _dbService.executeOperation<void>(
      'follows',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            await _createFollowInAlloyDb(followerId, followingId);
            break;
          case DatabaseType.redis:
            await _cacheFollowInRedis(followerId, followingId);
            break;
          default:
            throw Exception('Cannot create follow in $dbType');
        }
      },
      useCache: false,
    );
  }

  static Future<void> _unfollowUser(String followerId, String followingId) async {
    await _dbService.executeOperation<void>(
      'follows',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            await _deleteFollowFromAlloyDb(followerId, followingId);
            break;
          case DatabaseType.redis:
            await _removeFollowFromRedis(followerId, followingId);
            break;
          default:
            throw Exception('Cannot remove follow from $dbType');
        }
      },
      useCache: false,
    );
  }

  // Redis operations
  static Future<bool> _checkFollowStatusFromRedis(String followerId, String followingId) async {
    final redis = DatabaseConnectionManager().getRedisCommands();
    final result = await redis.send_object(['SISMEMBER', 'following:$followerId', followingId]);
    return result == 1;
  }

  static Future<Map<String, int>> _getFollowCountsFromRedis(String userId) async {
    final redis = DatabaseConnectionManager().getRedisCommands();
    final counts = await redis.send_object(['HGETALL', 'follow_count:$userId']);
    
    if (counts != null) {
      final countList = List.from(counts);
      final result = <String, int>{};
      
      for (int i = 0; i < countList.length; i += 2) {
        result[countList[i].toString()] = int.parse(countList[i + 1].toString());
      }
      
      return result;
    }
    
    return {'following': 0, 'followers': 0};
  }

  static Future<List<String>> _getFollowersFromRedis(String userId) async {
    final redis = DatabaseConnectionManager().getRedisCommands();
    final followers = await redis.send_object(['SMEMBERS', 'followers:$userId']);
    
    if (followers != null) {
      return List<String>.from(followers);
    }
    
    return [];
  }

  static Future<void> _cacheFollowInRedis(String followerId, String followingId) async {
    final redis = DatabaseConnectionManager().getRedisCommands();
    
    // Add to following set
    await redis.send_object(['SADD', 'following:$followerId', followingId]);
    // Add to followers set
    await redis.send_object(['SADD', 'followers:$followingId', followerId]);
    
    // Update counts
    await redis.send_object(['HINCRBY', 'follow_count:$followerId', 'following', 1]);
    await redis.send_object(['HINCRBY', 'follow_count:$followingId', 'followers', 1]);
    
    // Set TTL
    await redis.send_object(['EXPIRE', 'following:$followerId', 86400]); // 24 hours
    await redis.send_object(['EXPIRE', 'followers:$followingId', 86400]);
    await redis.send_object(['EXPIRE', 'follow_count:$followerId', 3600]); // 1 hour
    await redis.send_object(['EXPIRE', 'follow_count:$followingId', 3600]);
  }

  static Future<void> _removeFollowFromRedis(String followerId, String followingId) async {
    final redis = DatabaseConnectionManager().getRedisCommands();
    
    // Remove from following set
    await redis.send_object(['SREM', 'following:$followerId', followingId]);
    // Remove from followers set
    await redis.send_object(['SREM', 'followers:$followingId', followerId]);
    
    // Update counts
    await redis.send_object(['HINCRBY', 'follow_count:$followerId', 'following', -1]);
    await redis.send_object(['HINCRBY', 'follow_count:$followingId', 'followers', -1]);
  }

  // AlloyDB operations
  static Future<bool> _checkFollowStatusFromAlloyDb(String followerId, String followingId) async {
    final connection = await DatabaseConnectionManager().getAlloyDbConnection();
    try {
      final results = await connection.query(
        'SELECT 1 FROM follows WHERE follower_id = @followerId AND following_id = @followingId',
        substitutionValues: {
          'followerId': followerId,
          'followingId': followingId,
        },
      );
      return results.isNotEmpty;
    } finally {
      DatabaseConnectionManager().returnAlloyDbConnection(connection);
    }
  }

  static Future<Map<String, int>> _getFollowCountsFromAlloyDb(String userId) async {
    final connection = await DatabaseConnectionManager().getAlloyDbConnection();
    try {
      final results = await connection.query(
        'SELECT followers_count, following_count FROM users WHERE firebase_uid = @userId',
        substitutionValues: {'userId': userId},
      );
      
      if (results.isNotEmpty) {
        final row = results.first;
        return {
          'followers': row[0] as int,
          'following': row[1] as int,
        };
      }
      
      return {'following': 0, 'followers': 0};
    } finally {
      DatabaseConnectionManager().returnAlloyDbConnection(connection);
    }
  }

  static Future<List<String>> _getFollowersFromAlloyDb(String userId) async {
    final connection = await DatabaseConnectionManager().getAlloyDbConnection();
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
      DatabaseConnectionManager().returnAlloyDbConnection(connection);
    }
  }

  static Future<void> _createFollowInAlloyDb(String followerId, String followingId) async {
    final connection = await DatabaseConnectionManager().getAlloyDbConnection();
    try {
      await connection.query('''
        INSERT INTO follows (follower_id, following_id)
        SELECT f.id, t.id
        FROM users f, users t
        WHERE f.firebase_uid = @followerId AND t.firebase_uid = @followingId
        ON CONFLICT (follower_id, following_id) DO NOTHING
      ''', substitutionValues: {
        'followerId': followerId,
        'followingId': followingId,
      });
    } finally {
      DatabaseConnectionManager().returnAlloyDbConnection(connection);
    }
  }

  static Future<void> _deleteFollowFromAlloyDb(String followerId, String followingId) async {
    final connection = await DatabaseConnectionManager().getAlloyDbConnection();
    try {
      await connection.query('''
        DELETE FROM follows
        WHERE follower_id = (SELECT id FROM users WHERE firebase_uid = @followerId)
        AND following_id = (SELECT id FROM users WHERE firebase_uid = @followingId)
      ''', substitutionValues: {
        'followerId': followerId,
        'followingId': followingId,
      });
    } finally {
      DatabaseConnectionManager().returnAlloyDbConnection(connection);
    }
  }
}