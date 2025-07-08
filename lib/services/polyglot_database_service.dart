// Polyglot database service - routes operations to appropriate database
// Implements the polyglot persistence pattern with fallback strategies

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:postgres/postgres.dart';
import 'package:redis/redis.dart';
import 'database_connection_manager.dart';
import '../config/database_config.dart';
import '../models/countdown.dart';
import '../models/comment.dart';

class PolyglotDatabaseService {
  static final PolyglotDatabaseService _instance = PolyglotDatabaseService._internal();
  factory PolyglotDatabaseService() => _instance;
  PolyglotDatabaseService._internal();

  final DatabaseConnectionManager _connectionManager = DatabaseConnectionManager();
  
  // Initialize the service
  Future<void> initialize() async {
    await _connectionManager.initialize();
  }

  // Generic method to route data operations to appropriate database
  Future<T> executeOperation<T>(
    String dataType,
    Future<T> Function(DatabaseType dbType) operation, {
    bool useCache = true,
    Duration? cacheTimeout,
  }) async {
    final primaryDb = DatabaseConfig.dataTypeRouting[dataType] ?? DatabaseType.firestore;
    
    try {
      // Try cache first if enabled
      if (useCache && primaryDb != DatabaseType.redis) {
        final cached = await _tryCache<T>(dataType, operation);
        if (cached != null) return cached;
      }
      
      // Execute on primary database
      return await operation(primaryDb);
      
    } catch (e) {
      // Fallback strategy
      return await _executeWithFallback<T>(dataType, operation, primaryDb, e);
    }
  }

  // Try cache operation first
  Future<T?> _tryCache<T>(
    String dataType,
    Future<T> Function(DatabaseType dbType) operation,
  ) async {
    try {
      if (_connectionManager.getConnectionStatusFor(DatabaseType.redis) == ConnectionStatus.connected) {
        return await operation(DatabaseType.redis);
      }
    } catch (e) {
      // Cache miss or error, continue to primary database
      print('Cache miss for $dataType: $e');
    }
    return null;
  }

  // Execute with fallback strategy
  Future<T> _executeWithFallback<T>(
    String dataType,
    Future<T> Function(DatabaseType dbType) operation,
    DatabaseType primaryDb,
    dynamic primaryError,
  ) async {
    print('Primary database ($primaryDb) failed for $dataType: $primaryError');
    
    // Define fallback chain
    final fallbackChain = _getFallbackChain(primaryDb);
    
    for (final fallbackDb in fallbackChain) {
      try {
        if (_connectionManager.getConnectionStatusFor(fallbackDb) == ConnectionStatus.connected) {
          print('Attempting fallback to $fallbackDb for $dataType');
          return await operation(fallbackDb);
        }
      } catch (e) {
        print('Fallback to $fallbackDb failed: $e');
        continue;
      }
    }
    
    throw Exception('All databases failed for operation on $dataType. Primary error: $primaryError');
  }

  // Get fallback chain for database type
  List<DatabaseType> _getFallbackChain(DatabaseType primaryDb) {
    switch (primaryDb) {
      case DatabaseType.alloydb:
        return [DatabaseType.firestore, DatabaseType.analytics];
      case DatabaseType.firestore:
        return [DatabaseType.redis, DatabaseType.analytics];
      case DatabaseType.redis:
        return [DatabaseType.firestore, DatabaseType.alloydb];
      case DatabaseType.analytics:
        return [DatabaseType.redis, DatabaseType.firestore];
    }
  }

  // User operations (AlloyDB primary)
  Future<Map<String, dynamic>?> getUserById(String userId) async {
    return await executeOperation<Map<String, dynamic>?>(
      'users',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            return await _getUserFromAlloyDb(userId);
          case DatabaseType.firestore:
            return await _getUserFromFirestore(userId);
          case DatabaseType.redis:
            return await _getUserFromRedisCache(userId);
          default:
            throw Exception('Unsupported database type for user operations');
        }
      },
    );
  }

  Future<void> createUser(Map<String, dynamic> userData) async {
    return await executeOperation<void>(
      'users',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            await _createUserInAlloyDb(userData);
            break;
          case DatabaseType.firestore:
            await _createUserInFirestore(userData);
            break;
          default:
            throw Exception('Cannot create user in $dbType');
        }
        
        // Cache user data in Redis
        await _cacheUserData(userData);
      },
    );
  }

  // Post operations (AlloyDB primary)
  Future<List<Map<String, dynamic>>> getPostsByCategory(String category, {int limit = 20}) async {
    return await executeOperation<List<Map<String, dynamic>>>(
      'posts',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            return await _getPostsFromAlloyDb(category: category, limit: limit);
          case DatabaseType.firestore:
            return await _getPostsFromFirestore(category: category, limit: limit);
          case DatabaseType.analytics:
            return await _getPostsFromAnalytics(category: category, limit: limit);
          default:
            throw Exception('Unsupported database type for post operations');
        }
      },
    );
  }

  Future<void> createPost(Map<String, dynamic> postData) async {
    return await executeOperation<void>(
      'posts',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.alloydb:
            await _createPostInAlloyDb(postData);
            break;
          case DatabaseType.firestore:
            await _createPostInFirestore(postData);
            break;
          default:
            throw Exception('Cannot create post in $dbType');
        }
        
        // Trigger fanout to Redis and Firestore
        await _triggerPostFanout(postData);
      },
    );
  }

  // Timeline operations (Firestore primary, Redis cache)
  Future<List<Map<String, dynamic>>> getUserTimeline(String userId, {int limit = 20}) async {
    return await executeOperation<List<Map<String, dynamic>>>(
      'user_timelines',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.redis:
            return await _getTimelineFromRedis(userId, limit: limit);
          case DatabaseType.firestore:
            return await _getTimelineFromFirestore(userId, limit: limit);
          case DatabaseType.analytics:
            return await _getTimelineFromAnalytics(userId, limit: limit);
          default:
            throw Exception('Unsupported database type for timeline operations');
        }
      },
    );
  }

  // Notification operations (Firestore primary)
  Future<List<Map<String, dynamic>>> getUserNotifications(String userId, {int limit = 50}) async {
    return await executeOperation<List<Map<String, dynamic>>>(
      'notifications',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.firestore:
            return await _getNotificationsFromFirestore(userId, limit: limit);
          case DatabaseType.redis:
            return await _getNotificationsFromRedis(userId, limit: limit);
          default:
            throw Exception('Unsupported database type for notification operations');
        }
      },
    );
  }

  // Counter operations (Redis primary)
  Future<Map<String, int>> getPostCounters(String postId) async {
    return await executeOperation<Map<String, int>>(
      'counters',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.redis:
            return await _getCountersFromRedis(postId);
          case DatabaseType.alloydb:
            return await _getCountersFromAlloyDb(postId);
          case DatabaseType.analytics:
            return await _getCountersFromAnalytics(postId);
          default:
            throw Exception('Unsupported database type for counter operations');
        }
      },
    );
  }

  Future<void> incrementCounter(String postId, String counterType) async {
    return await executeOperation<void>(
      'counters',
      (dbType) async {
        switch (dbType) {
          case DatabaseType.redis:
            await _incrementCounterInRedis(postId, counterType);
            break;
          case DatabaseType.alloydb:
            await _incrementCounterInAlloyDb(postId, counterType);
            break;
          default:
            throw Exception('Cannot increment counter in $dbType');
        }
      },
    );
  }

  // Implementation methods for AlloyDB operations
  Future<Map<String, dynamic>?> _getUserFromAlloyDb(String userId) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      final results = await connection.query(
        'SELECT * FROM users WHERE firebase_uid = @userId',
        substitutionValues: {'userId': userId},
      );
      
      if (results.isNotEmpty) {
        return results.first.toColumnMap();
      }
      return null;
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  Future<void> _createUserInAlloyDb(Map<String, dynamic> userData) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      await connection.query('''
        INSERT INTO users (firebase_uid, username, display_name, email, profile_image_url, bio)
        VALUES (@firebaseUid, @username, @displayName, @email, @profileImageUrl, @bio)
      ''', substitutionValues: {
        'firebaseUid': userData['firebase_uid'],
        'username': userData['username'],
        'displayName': userData['display_name'],
        'email': userData['email'],
        'profileImageUrl': userData['profile_image_url'],
        'bio': userData['bio'],
      });
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  Future<List<Map<String, dynamic>>> _getPostsFromAlloyDb({String? category, int limit = 20}) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      String query = '''
        SELECT p.*, u.username as creator_username, u.display_name as creator_display_name
        FROM posts p
        JOIN users u ON p.creator_id = u.id
        WHERE p.status = 'visible'
      ''';
      
      final substitutionValues = <String, dynamic>{};
      
      if (category != null) {
        query += ' AND p.category = @category';
        substitutionValues['category'] = category;
      }
      
      query += ' ORDER BY p.created_at DESC LIMIT @limit';
      substitutionValues['limit'] = limit;
      
      final results = await connection.query(query, substitutionValues: substitutionValues);
      return results.map((row) => row.toColumnMap()).toList();
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  Future<void> _createPostInAlloyDb(Map<String, dynamic> postData) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      await connection.query('''
        INSERT INTO posts (creator_id, event_name, description, category, event_date, image_url, hashtags)
        VALUES (@creatorId, @eventName, @description, @category, @eventDate, @imageUrl, @hashtags)
      ''', substitutionValues: {
        'creatorId': postData['creator_id'],
        'eventName': postData['event_name'],
        'description': postData['description'],
        'category': postData['category'],
        'eventDate': postData['event_date'],
        'imageUrl': postData['image_url'],
        'hashtags': postData['hashtags'],
      });
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  // Implementation methods for Firestore operations
  Future<Map<String, dynamic>?> _getUserFromFirestore(String userId) async {
    final firestore = _connectionManager.getFirestore();
    final doc = await firestore.collection('users').doc(userId).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> _createUserInFirestore(Map<String, dynamic> userData) async {
    final firestore = _connectionManager.getFirestore();
    await firestore.collection('users').doc(userData['firebase_uid']).set(userData);
  }

  Future<List<Map<String, dynamic>>> _getTimelineFromFirestore(String userId, {int limit = 20}) async {
    final firestore = _connectionManager.getFirestore();
    final doc = await firestore.collection('user_timelines').doc(userId).get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final timelineItems = List<Map<String, dynamic>>.from(data['timelineItems'] ?? []);
      return timelineItems.take(limit).toList();
    }
    
    return [];
  }

  Future<List<Map<String, dynamic>>> _getNotificationsFromFirestore(String userId, {int limit = 50}) async {
    final firestore = _connectionManager.getFirestore();
    final query = await firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    
    return query.docs.map((doc) => doc.data()).toList();
  }

  // Implementation methods for Redis operations
  Future<Map<String, dynamic>?> _getUserFromRedisCache(String userId) async {
    final redis = _connectionManager.getRedisCommands();
    final cached = await redis.send_object(['GET', 'user:$userId']);
    
    if (cached != null) {
      return json.decode(cached.toString());
    }
    return null;
  }

  Future<void> _cacheUserData(Map<String, dynamic> userData) async {
    final redis = _connectionManager.getRedisCommands();
    await redis.send_object([
      'SETEX',
      'user:${userData['firebase_uid']}',
      DatabaseConfig.cacheTtl['user_sessions']!,
      json.encode(userData),
    ]);
  }

  Future<List<Map<String, dynamic>>> _getTimelineFromRedis(String userId, {int limit = 20}) async {
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
        final postData = items[i].toString().split(':');
        if (postData.length >= 4) {
          timeline.add({
            'postId': postData[0],
            'category': postData[1],
            'eventDate': postData[2],
            'score': double.parse(items[i + 1].toString()),
          });
        }
      }
      
      return timeline;
    }
    
    return [];
  }

  Future<Map<String, int>> _getCountersFromRedis(String postId) async {
    final redis = _connectionManager.getRedisCommands();
    final counters = await redis.send_object(['HGETALL', 'counter:$postId']);
    
    if (counters != null) {
      final counterList = List.from(counters);
      final result = <String, int>{};
      
      for (int i = 0; i < counterList.length; i += 2) {
        result[counterList[i].toString()] = int.parse(counterList[i + 1].toString());
      }
      
      return result;
    }
    
    return {'likes': 0, 'comments': 0, 'views': 0, 'participants': 0};
  }

  Future<void> _incrementCounterInRedis(String postId, String counterType) async {
    final redis = _connectionManager.getRedisCommands();
    await redis.send_object(['HINCRBY', 'counter:$postId', counterType, 1]);
    
    // Set TTL if this is a new counter
    await redis.send_object(['EXPIRE', 'counter:$postId', DatabaseConfig.cacheTtl['post_counters']!]);
  }

  // Analytics service operations
  Future<List<Map<String, dynamic>>> _getPostsFromAnalytics({String? category, int limit = 20}) async {
    final response = await _connectionManager.executeAnalyticsRequest(
      '/posts',
      body: {
        'category': category,
        'limit': limit,
      },
      method: 'POST',
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['posts'] ?? []);
    }
    
    throw Exception('Analytics service request failed: ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> _getTimelineFromAnalytics(String userId, {int limit = 20}) async {
    final response = await _connectionManager.executeAnalyticsRequest(
      '/timeline/$userId',
      body: {'limit': limit},
      method: 'POST',
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['timeline'] ?? []);
    }
    
    throw Exception('Analytics service request failed: ${response.statusCode}');
  }

  // Fanout processing
  Future<void> _triggerPostFanout(Map<String, dynamic> postData) async {
    final redis = _connectionManager.getRedisCommands();
    
    // Add to fanout queue
    final fanoutJob = {
      'postId': postData['id'],
      'creatorId': postData['creator_id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'postData': postData,
    };
    
    await redis.send_object([
      'LPUSH',
      'fanout_queue',
      json.encode(fanoutJob),
    ]);
  }

  // Fallback implementations
  Future<Map<String, int>> _getCountersFromAlloyDb(String postId) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      final results = await connection.query(
        'SELECT likes_count, comments_count, views_count, participants_count FROM posts WHERE id = @postId',
        substitutionValues: {'postId': postId},
      );
      
      if (results.isNotEmpty) {
        final row = results.first;
        return {
          'likes': row[0] as int,
          'comments': row[1] as int,
          'views': row[2] as int,
          'participants': row[3] as int,
        };
      }
      
      return {'likes': 0, 'comments': 0, 'views': 0, 'participants': 0};
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  Future<void> _incrementCounterInAlloyDb(String postId, String counterType) async {
    final connection = await _connectionManager.getAlloyDbConnection();
    try {
      final columnName = '${counterType}_count';
      await connection.query(
        'UPDATE posts SET $columnName = $columnName + 1 WHERE id = @postId',
        substitutionValues: {'postId': postId},
      );
    } finally {
      _connectionManager.returnAlloyDbConnection(connection);
    }
  }

  // Get service health status
  Map<String, dynamic> getHealthStatus() {
    final connectionStatus = _connectionManager.getConnectionStatus();
    final lastHealthChecks = _connectionManager.getLastHealthCheckTimes();
    
    return {
      'connections': connectionStatus.map((key, value) => MapEntry(key.toString(), value.toString())),
      'lastHealthChecks': lastHealthChecks.map((key, value) => MapEntry(key, value.toIso8601String())),
      'allConnected': _connectionManager.areAllDatabasesConnected(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Dispose resources
  Future<void> dispose() async {
    await _connectionManager.dispose();
  }
}