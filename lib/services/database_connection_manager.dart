// Database connection manager for polyglot persistence
// Manages connections to AlloyDB, Firestore, Redis, and Analytics Service

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:postgres/postgres.dart';
import 'package:redis/redis.dart';
import 'package:http/http.dart' as http;
import '../config/database_config.dart';

class DatabaseConnectionManager {
  static final DatabaseConnectionManager _instance = DatabaseConnectionManager._internal();
  factory DatabaseConnectionManager() => _instance;
  DatabaseConnectionManager._internal();

  // Connection instances
  PostgreSQLConnection? _alloyDbConnection;
  FirebaseFirestore? _firestoreInstance;
  RedisConnection? _redisConnection;
  Command? _redisCommands;
  
  // Connection status tracking
  final Map<DatabaseType, ConnectionStatus> _connectionStatus = {
    DatabaseType.alloydb: ConnectionStatus.disconnected,
    DatabaseType.firestore: ConnectionStatus.disconnected,
    DatabaseType.redis: ConnectionStatus.disconnected,
    DatabaseType.analytics: ConnectionStatus.disconnected,
  };
  
  // Connection pools
  final List<PostgreSQLConnection> _alloyDbPool = [];
  final Map<String, DateTime> _lastHealthCheck = {};
  
  // Health check timer
  Timer? _healthCheckTimer;
  
  // Initialize all database connections
  Future<void> initialize() async {
    await Future.wait([
      _initializeAlloyDb(),
      _initializeFirestore(),
      _initializeRedis(),
      _testAnalyticsService(),
    ]);
    
    // Start health monitoring
    _startHealthMonitoring();
  }
  
  // Initialize AlloyDB PostgreSQL connection
  Future<void> _initializeAlloyDb() async {
    try {
      _connectionStatus[DatabaseType.alloydb] = ConnectionStatus.connecting;
      
      // Create main connection
      _alloyDbConnection = PostgreSQLConnection(
        DatabaseConfig.alloyDbHost,
        DatabaseConfig.alloyDbPort,
        DatabaseConfig.alloyDbName,
        username: DatabaseConfig.alloyDbUser,
        password: DatabaseConfig.alloyDbPassword,
        timeoutInSeconds: DatabaseConfig.connectionTimeout.inSeconds,
        queryTimeoutInSeconds: DatabaseConfig.queryTimeout.inSeconds,
      );
      
      await _alloyDbConnection!.open();
      
      // Initialize connection pool
      await _initializeAlloyDbPool();
      
      _connectionStatus[DatabaseType.alloydb] = ConnectionStatus.connected;
      print('✅ AlloyDB connection established');
      
    } catch (e) {
      _connectionStatus[DatabaseType.alloydb] = ConnectionStatus.error;
      print('❌ AlloyDB connection failed: $e');
      rethrow;
    }
  }
  
  // Initialize AlloyDB connection pool
  Future<void> _initializeAlloyDbPool() async {
    for (int i = 0; i < DatabaseConfig.minConnectionPoolSize; i++) {
      final connection = PostgreSQLConnection(
        DatabaseConfig.alloyDbHost,
        DatabaseConfig.alloyDbPort,
        DatabaseConfig.alloyDbName,
        username: DatabaseConfig.alloyDbUser,
        password: DatabaseConfig.alloyDbPassword,
        timeoutInSeconds: DatabaseConfig.connectionTimeout.inSeconds,
        queryTimeoutInSeconds: DatabaseConfig.queryTimeout.inSeconds,
      );
      
      await connection.open();
      _alloyDbPool.add(connection);
    }
  }
  
  // Initialize Firestore connection
  Future<void> _initializeFirestore() async {
    try {
      _connectionStatus[DatabaseType.firestore] = ConnectionStatus.connecting;
      
      _firestoreInstance = FirebaseFirestore.instance;
      
      // Configure Firestore settings
      _firestoreInstance!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      
      // Test connection with a simple query
      await _firestoreInstance!.collection('health_check').limit(1).get();
      
      _connectionStatus[DatabaseType.firestore] = ConnectionStatus.connected;
      print('✅ Firestore connection established');
      
    } catch (e) {
      _connectionStatus[DatabaseType.firestore] = ConnectionStatus.error;
      print('❌ Firestore connection failed: $e');
      rethrow;
    }
  }
  
  // Initialize Redis connection
  Future<void> _initializeRedis() async {
    try {
      _connectionStatus[DatabaseType.redis] = ConnectionStatus.connecting;
      
      _redisConnection = RedisConnection();
      
      await _redisConnection!.connect(
        DatabaseConfig.redisHost,
        DatabaseConfig.redisPort,
      );
      
      _redisCommands = _redisConnection!.get_command();
      
      // Authenticate if password is provided
      if (DatabaseConfig.redisPassword.isNotEmpty) {
        await _redisCommands!.send_object(['AUTH', DatabaseConfig.redisPassword]);
      }
      
      // Select database
      if (DatabaseConfig.redisDb > 0) {
        await _redisCommands!.send_object(['SELECT', DatabaseConfig.redisDb]);
      }
      
      // Test connection
      final response = await _redisCommands!.send_object(['PING']);
      if (response != 'PONG') {
        throw Exception('Redis ping failed');
      }
      
      _connectionStatus[DatabaseType.redis] = ConnectionStatus.connected;
      print('✅ Redis connection established');
      
    } catch (e) {
      _connectionStatus[DatabaseType.redis] = ConnectionStatus.error;
      print('❌ Redis connection failed: $e');
      rethrow;
    }
  }
  
  // Test Analytics Service connectivity
  Future<void> _testAnalyticsService() async {
    try {
      _connectionStatus[DatabaseType.analytics] = ConnectionStatus.connecting;
      
      final response = await http.get(
        Uri.parse('${DatabaseConfig.analyticsServiceUrl}/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(DatabaseConfig.connectionTimeout);
      
      if (response.statusCode == 200) {
        _connectionStatus[DatabaseType.analytics] = ConnectionStatus.connected;
        print('✅ Analytics Service connection established');
      } else {
        throw Exception('Analytics Service health check failed: ${response.statusCode}');
      }
      
    } catch (e) {
      _connectionStatus[DatabaseType.analytics] = ConnectionStatus.error;
      print('❌ Analytics Service connection failed: $e');
      rethrow;
    }
  }
  
  // Get AlloyDB connection from pool
  Future<PostgreSQLConnection> getAlloyDbConnection() async {
    if (_connectionStatus[DatabaseType.alloydb] != ConnectionStatus.connected) {
      throw Exception('AlloyDB not connected');
    }
    
    // Return connection from pool or create new one if pool is full
    if (_alloyDbPool.isNotEmpty) {
      return _alloyDbPool.removeAt(0);
    }
    
    // Create new connection if under max pool size
    if (_alloyDbPool.length < DatabaseConfig.maxConnectionPoolSize) {
      final connection = PostgreSQLConnection(
        DatabaseConfig.alloyDbHost,
        DatabaseConfig.alloyDbPort,
        DatabaseConfig.alloyDbName,
        username: DatabaseConfig.alloyDbUser,
        password: DatabaseConfig.alloyDbPassword,
        timeoutInSeconds: DatabaseConfig.connectionTimeout.inSeconds,
        queryTimeoutInSeconds: DatabaseConfig.queryTimeout.inSeconds,
      );
      
      await connection.open();
      return connection;
    }
    
    // Wait for connection to be available
    while (_alloyDbPool.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return _alloyDbPool.removeAt(0);
  }
  
  // Return AlloyDB connection to pool
  void returnAlloyDbConnection(PostgreSQLConnection connection) {
    if (_alloyDbPool.length < DatabaseConfig.maxConnectionPoolSize) {
      _alloyDbPool.add(connection);
    } else {
      connection.close();
    }
  }
  
  // Get Firestore instance
  FirebaseFirestore getFirestore() {
    if (_connectionStatus[DatabaseType.firestore] != ConnectionStatus.connected) {
      throw Exception('Firestore not connected');
    }
    return _firestoreInstance!;
  }
  
  // Get Redis commands
  Command getRedisCommands() {
    if (_connectionStatus[DatabaseType.redis] != ConnectionStatus.connected) {
      throw Exception('Redis not connected');
    }
    return _redisCommands!;
  }
  
  // Execute Analytics Service request
  Future<http.Response> executeAnalyticsRequest(String endpoint, {
    Map<String, dynamic>? body,
    String method = 'GET',
  }) async {
    if (_connectionStatus[DatabaseType.analytics] != ConnectionStatus.connected) {
      throw Exception('Analytics Service not connected');
    }
    
    final uri = Uri.parse('${DatabaseConfig.analyticsServiceUrl}$endpoint');
    
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: {'Content-Type': 'application/json'});
      case 'POST':
        return await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body != null ? json.encode(body) : null,
        );
      case 'PUT':
        return await http.put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body != null ? json.encode(body) : null,
        );
      case 'DELETE':
        return await http.delete(uri, headers: {'Content-Type': 'application/json'});
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
  
  // Start health monitoring
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(
      DatabaseConfig.healthCheckInterval,
      (timer) => _performHealthChecks(),
    );
  }
  
  // Perform health checks on all connections
  Future<void> _performHealthChecks() async {
    await Future.wait([
      _checkAlloyDbHealth(),
      _checkFirestoreHealth(),
      _checkRedisHealth(),
      _checkAnalyticsHealth(),
    ]);
  }
  
  // Check AlloyDB health
  Future<void> _checkAlloyDbHealth() async {
    try {
      if (_alloyDbConnection != null && !_alloyDbConnection!.isClosed) {
        await _alloyDbConnection!.query('SELECT 1');
        _connectionStatus[DatabaseType.alloydb] = ConnectionStatus.connected;
      } else {
        await _initializeAlloyDb();
      }
      _lastHealthCheck['alloydb'] = DateTime.now();
    } catch (e) {
      _connectionStatus[DatabaseType.alloydb] = ConnectionStatus.error;
      print('⚠️ AlloyDB health check failed: $e');
      // Attempt reconnection
      await _attemptReconnection(DatabaseType.alloydb);
    }
  }
  
  // Check Firestore health
  Future<void> _checkFirestoreHealth() async {
    try {
      await _firestoreInstance!.collection('health_check').limit(1).get();
      _connectionStatus[DatabaseType.firestore] = ConnectionStatus.connected;
      _lastHealthCheck['firestore'] = DateTime.now();
    } catch (e) {
      _connectionStatus[DatabaseType.firestore] = ConnectionStatus.error;
      print('⚠️ Firestore health check failed: $e');
      await _attemptReconnection(DatabaseType.firestore);
    }
  }
  
  // Check Redis health
  Future<void> _checkRedisHealth() async {
    try {
      final response = await _redisCommands!.send_object(['PING']);
      if (response == 'PONG') {
        _connectionStatus[DatabaseType.redis] = ConnectionStatus.connected;
        _lastHealthCheck['redis'] = DateTime.now();
      } else {
        throw Exception('Invalid ping response');
      }
    } catch (e) {
      _connectionStatus[DatabaseType.redis] = ConnectionStatus.error;
      print('⚠️ Redis health check failed: $e');
      await _attemptReconnection(DatabaseType.redis);
    }
  }
  
  // Check Analytics Service health
  Future<void> _checkAnalyticsHealth() async {
    try {
      final response = await http.get(
        Uri.parse('${DatabaseConfig.analyticsServiceUrl}/health'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        _connectionStatus[DatabaseType.analytics] = ConnectionStatus.connected;
        _lastHealthCheck['analytics'] = DateTime.now();
      } else {
        throw Exception('Health check returned ${response.statusCode}');
      }
    } catch (e) {
      _connectionStatus[DatabaseType.analytics] = ConnectionStatus.error;
      print('⚠️ Analytics Service health check failed: $e');
      await _attemptReconnection(DatabaseType.analytics);
    }
  }
  
  // Attempt reconnection with exponential backoff
  Future<void> _attemptReconnection(DatabaseType dbType) async {
    if (!DatabaseConfig.enableFailover) return;
    
    for (int attempt = 1; attempt <= DatabaseConfig.maxRetries; attempt++) {
      try {
        print('🔄 Attempting reconnection to $dbType (attempt $attempt)');
        
        switch (dbType) {
          case DatabaseType.alloydb:
            await _initializeAlloyDb();
            break;
          case DatabaseType.firestore:
            await _initializeFirestore();
            break;
          case DatabaseType.redis:
            await _initializeRedis();
            break;
          case DatabaseType.analytics:
            await _testAnalyticsService();
            break;
        }
        
        print('✅ Reconnection to $dbType successful');
        return;
        
      } catch (e) {
        if (attempt == DatabaseConfig.maxRetries) {
          print('❌ Max reconnection attempts reached for $dbType');
          _connectionStatus[dbType] = ConnectionStatus.error;
        } else {
          // Exponential backoff
          final delay = DatabaseConfig.retryDelay * (2 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
  }
  
  // Get connection status for all databases
  Map<DatabaseType, ConnectionStatus> getConnectionStatus() {
    return Map.from(_connectionStatus);
  }
  
  // Get connection status for specific database
  ConnectionStatus getConnectionStatusFor(DatabaseType dbType) {
    return _connectionStatus[dbType] ?? ConnectionStatus.disconnected;
  }
  
  // Check if all critical databases are connected
  bool areAllDatabasesConnected() {
    return _connectionStatus.values.every(
      (status) => status == ConnectionStatus.connected,
    );
  }
  
  // Get last health check times
  Map<String, DateTime> getLastHealthCheckTimes() {
    return Map.from(_lastHealthCheck);
  }
  
  // Graceful shutdown
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    
    // Close AlloyDB connections
    await _alloyDbConnection?.close();
    for (final connection in _alloyDbPool) {
      await connection.close();
    }
    
    // Close Redis connection
    await _redisConnection?.close();
    
    print('🔌 All database connections closed');
  }
}

// Database connection health information
class DatabaseHealth {
  final DatabaseType type;
  final ConnectionStatus status;
  final DateTime? lastHealthCheck;
  final Duration? responseTime;
  final String? errorMessage;
  
  const DatabaseHealth({
    required this.type,
    required this.status,
    this.lastHealthCheck,
    this.responseTime,
    this.errorMessage,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'status': status.toString(),
      'lastHealthCheck': lastHealthCheck?.toIso8601String(),
      'responseTime': responseTime?.inMilliseconds,
      'errorMessage': errorMessage,
    };
  }
}