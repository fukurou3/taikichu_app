// Database configuration for polyglot persistence architecture
// Manages connections to AlloyDB, Firestore, and Redis

class DatabaseConfig {
  // AlloyDB PostgreSQL Configuration
  static const String alloyDbHost = String.fromEnvironment(
    'ALLOYDB_HOST',
    defaultValue: 'localhost'
  );
  
  static const int alloyDbPort = int.fromEnvironment(
    'ALLOYDB_PORT',
    defaultValue: 5432
  );
  
  static const String alloyDbName = String.fromEnvironment(
    'ALLOYDB_DATABASE',
    defaultValue: 'taikichu_main'
  );
  
  static const String alloyDbUser = String.fromEnvironment(
    'ALLOYDB_USER',
    defaultValue: 'app_user'
  );
  
  static const String alloyDbPassword = String.fromEnvironment(
    'ALLOYDB_PASSWORD',
    defaultValue: ''
  );
  
  // Redis Configuration
  static const String redisHost = String.fromEnvironment(
    'REDIS_HOST',
    defaultValue: 'localhost'
  );
  
  static const int redisPort = int.fromEnvironment(
    'REDIS_PORT',
    defaultValue: 6379
  );
  
  static const String redisPassword = String.fromEnvironment(
    'REDIS_PASSWORD',
    defaultValue: ''
  );
  
  static const int redisDb = int.fromEnvironment(
    'REDIS_DB',
    defaultValue: 0
  );
  
  // Analytics Service Configuration  
  static const String analyticsServiceUrl = String.fromEnvironment(
    'ANALYTICS_SERVICE_URL',
    defaultValue: 'https://analytics-service-694414843228.asia-northeast1.run.app'
  );
  
  // Firebase Configuration (already configured)
  static const String firebaseProjectId = 'taikichu-app-c8dcd';
  
  // Database usage routing configuration
  static const Map<String, DatabaseType> dataTypeRouting = {
    // Core relational data -> AlloyDB
    'users': DatabaseType.alloydb,
    'posts': DatabaseType.alloydb,
    'follows': DatabaseType.alloydb,
    'comments': DatabaseType.alloydb,
    'likes': DatabaseType.alloydb,
    'admin_roles': DatabaseType.alloydb,
    'moderation_logs': DatabaseType.alloydb,
    
    // Real-time and timeline data -> Firestore
    'user_timelines': DatabaseType.firestore,
    'global_timelines': DatabaseType.firestore,
    'notifications': DatabaseType.firestore,
    'real_time_activities': DatabaseType.firestore,
    'trending_data': DatabaseType.firestore,
    'live_events': DatabaseType.firestore,
    
    // High-speed caching -> Redis
    'timeline_cache': DatabaseType.redis,
    'counters': DatabaseType.redis,
    'user_sessions': DatabaseType.redis,
    'fanout_queues': DatabaseType.redis,
    'rate_limiting': DatabaseType.redis,
  };
  
  // Cache TTL configurations (in seconds)
  static const Map<String, int> cacheTtl = {
    'user_timeline': 604800, // 7 days
    'global_timeline': 3600, // 1 hour
    'category_timeline': 7200, // 2 hours
    'post_counters': 2592000, // 30 days
    'follow_relationships': 86400, // 24 hours
    'user_sessions': 604800, // 7 days
    'notifications': 604800, // 7 days
    'trending_data': 7200, // 2 hours
  };
  
  // Connection pool settings
  static const int maxConnectionPoolSize = 20;
  static const int minConnectionPoolSize = 5;
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration queryTimeout = Duration(seconds: 60);
  
  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);
  
  // Health check intervals
  static const Duration healthCheckInterval = Duration(minutes: 5);
  
  // Failover configuration
  static const bool enableFailover = true;
  static const Duration failoverTimeout = Duration(seconds: 10);
}

enum DatabaseType {
  alloydb,
  firestore, 
  redis,
  analytics
}

// Database connection status
enum ConnectionStatus {
  connected,
  disconnected,
  connecting,
  error,
  failover
}