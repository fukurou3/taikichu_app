# Polyglot Persistence Migration Guide

## Overview
This guide outlines the migration from a single Firebase Firestore database to a polyglot persistence architecture using AlloyDB for PostgreSQL, Firestore, and Redis.

## Migration Strategy

### Phase 1: Infrastructure Setup
1. **AlloyDB Cluster Setup**
   - Create AlloyDB cluster in Google Cloud
   - Configure primary and read replica instances
   - Set up connection pooling and security

2. **Redis Cache Setup**
   - Deploy Memorystore for Redis instance
   - Configure memory optimization settings
   - Set up Redis cluster for high availability

3. **Network Configuration**
   - Configure VPC peering between services
   - Set up private service connect
   - Configure firewall rules

### Phase 2: Schema Migration
1. **Create AlloyDB Schema**
   ```bash
   psql -h $ALLOYDB_HOST -U $ALLOYDB_USER -d $ALLOYDB_DATABASE -f database/alloydb_schema.sql
   ```

2. **Configure Firestore Collections**
   - Set up new Firestore collections based on `database/firestore_schema.md`
   - Configure security rules
   - Set up indexes

3. **Initialize Redis Key Patterns**
   - No schema creation needed for Redis
   - Key patterns defined in `database/redis_schema.md`

### Phase 3: Data Migration

#### User Data Migration (Firestore → AlloyDB)
```sql
-- Migration script for user data
WITH firestore_users AS (
  SELECT 
    firebase_uid,
    username,
    display_name,
    email,
    profile_image_url,
    bio,
    created_at,
    followers_count,
    following_count,
    posts_count
  FROM firestore_export.users
)
INSERT INTO users (
  firebase_uid, username, display_name, email, 
  profile_image_url, bio, created_at,
  followers_count, following_count, posts_count
)
SELECT * FROM firestore_users
ON CONFLICT (firebase_uid) DO UPDATE SET
  username = EXCLUDED.username,
  display_name = EXCLUDED.display_name,
  updated_at = NOW();
```

#### Post Data Migration (Firestore → AlloyDB)
```sql
-- Migration script for post data
WITH firestore_posts AS (
  SELECT 
    id,
    creator_id,
    event_name,
    description,
    category,
    event_date,
    image_url,
    participants_count,
    likes_count,
    comments_count,
    views_count,
    status,
    hashtags,
    created_at
  FROM firestore_export.posts
)
INSERT INTO posts (
  id, creator_id, event_name, description, category,
  event_date, image_url, participants_count,
  likes_count, comments_count, views_count,
  status, hashtags, created_at
)
SELECT 
  fp.*
FROM firestore_posts fp
JOIN users u ON fp.creator_id = u.firebase_uid
ON CONFLICT (id) DO UPDATE SET
  event_name = EXCLUDED.event_name,
  description = EXCLUDED.description,
  updated_at = NOW();
```

#### Follow Relationships Migration
```sql
-- Migration script for follow relationships
WITH firestore_follows AS (
  SELECT 
    follower_id,
    following_id,
    created_at
  FROM firestore_export.follows
)
INSERT INTO follows (follower_id, following_id, created_at)
SELECT 
  f1.id as follower_id,
  f2.id as following_id,
  ff.created_at
FROM firestore_follows ff
JOIN users f1 ON ff.follower_id = f1.firebase_uid
JOIN users f2 ON ff.following_id = f2.firebase_uid
ON CONFLICT (follower_id, following_id) DO NOTHING;
```

### Phase 4: Timeline Data Setup (Firestore)
```javascript
// Firestore migration script for timeline data
const admin = require('firebase-admin');
const fs = admin.firestore();

async function migrateTimelineData() {
  // Create user timeline collections
  const users = await fs.collection('users').get();
  
  for (const userDoc of users.docs) {
    const userId = userDoc.id;
    
    // Initialize user timeline document
    await fs.collection('user_timelines').doc(userId).set({
      userId: userId,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      timelineItems: [],
      metadata: {
        totalItems: 0,
        lastPostTimestamp: null,
        categories: [],
        isOptimized: false
      }
    });
  }
  
  // Create global timeline
  await fs.collection('global_timelines').doc('global').set({
    type: 'global',
    categoryName: null,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    timelineItems: [],
    metadata: {
      totalPosts: 0,
      lastRefresh: admin.firestore.FieldValue.serverTimestamp(),
      refreshInterval: 60,
      maxItems: 1000
    }
  });
}
```

### Phase 5: Service Layer Migration

#### Update Application Code
1. **Replace direct Firestore calls with PolyglotDatabaseService**
   ```dart
   // Before
   final users = await FirebaseFirestore.instance.collection('users').get();
   
   // After
   final userData = await PolyglotDatabaseService().getUserById(userId);
   ```

2. **Update Timeline Services**
   ```dart
   // Before
   final timeline = await getTimelineFromFirestore(userId);
   
   // After
   final timeline = await FanoutTimelineService.getUserTimeline(userId);
   ```

3. **Implement Caching Layer**
   ```dart
   // Add Redis caching to existing operations
   final cached = await RedisCache.get(key);
   if (cached != null) return cached;
   
   final data = await database.query();
   await RedisCache.set(key, data, ttl: Duration(hours: 1));
   ```

### Phase 6: Gradual Rollout

#### Feature Flags for Database Selection
```dart
class DatabaseRouter {
  static bool usePolyglotForUsers() {
    return FeatureFlags.isEnabled('polyglot_users');
  }
  
  static bool usePolyglotForTimelines() {
    return FeatureFlags.isEnabled('polyglot_timelines');
  }
}
```

#### A/B Testing Configuration
```dart
// Implement gradual rollout
final userSegment = getUserSegment(userId);
if (userSegment == 'polyglot_beta') {
  return await PolyglotDatabaseService().getUserTimeline(userId);
} else {
  return await LegacyTimelineService.getTimeline(userId);
}
```

### Phase 7: Performance Monitoring

#### Database Performance Metrics
```dart
class DatabaseMetrics {
  static void recordQuery(String database, String operation, Duration duration) {
    final metrics = {
      'database': database,
      'operation': operation,
      'duration_ms': duration.inMilliseconds,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Send to monitoring service
    MonitoringService.recordMetric('database_query', metrics);
  }
}
```

#### Redis Cache Hit Rate Monitoring
```dart
class CacheMetrics {
  static void recordCacheHit(String key) {
    MonitoringService.increment('cache_hit', tags: {'key_type': getKeyType(key)});
  }
  
  static void recordCacheMiss(String key) {
    MonitoringService.increment('cache_miss', tags: {'key_type': getKeyType(key)});
  }
}
```

## Migration Timeline

### Week 1-2: Infrastructure Setup
- [ ] Set up AlloyDB cluster
- [ ] Configure Redis instance
- [ ] Set up monitoring and alerting
- [ ] Create VPC and networking

### Week 3: Schema Creation
- [ ] Deploy AlloyDB schema
- [ ] Configure Firestore collections
- [ ] Set up Redis key patterns
- [ ] Create database indexes

### Week 4-5: Data Migration
- [ ] Export data from existing Firestore
- [ ] Migrate user data to AlloyDB
- [ ] Migrate post data to AlloyDB
- [ ] Migrate follow relationships
- [ ] Set up timeline data in Firestore

### Week 6: Service Layer Updates
- [ ] Deploy PolyglotDatabaseService
- [ ] Update timeline services
- [ ] Implement caching layer
- [ ] Add fallback mechanisms

### Week 7-8: Testing and Rollout
- [ ] Deploy with feature flags
- [ ] A/B test with 10% of users
- [ ] Monitor performance metrics
- [ ] Gradually increase rollout percentage

### Week 9: Full Migration
- [ ] Switch 100% of traffic to polyglot system
- [ ] Remove legacy code paths
- [ ] Optimize performance based on metrics
- [ ] Document final architecture

## Rollback Plan

### Immediate Rollback (< 1 hour)
1. **Disable Feature Flags**
   ```dart
   FeatureFlags.disable('polyglot_users');
   FeatureFlags.disable('polyglot_timelines');
   ```

2. **Route Traffic to Legacy System**
   ```dart
   DatabaseRouter.forceUseLegacy = true;
   ```

### Data Consistency Rollback
1. **Export current AlloyDB data**
   ```bash
   pg_dump -h $ALLOYDB_HOST -U $ALLOYDB_USER $ALLOYDB_DATABASE > rollback_data.sql
   ```

2. **Import back to Firestore**
   ```javascript
   // Convert PostgreSQL export to Firestore format
   const convertAndImport = require('./scripts/postgres-to-firestore');
   await convertAndImport('rollback_data.sql');
   ```

## Post-Migration Optimization

### Database Tuning
1. **AlloyDB Performance Tuning**
   ```sql
   -- Optimize for read-heavy workloads
   ALTER SYSTEM SET shared_buffers = '25% of RAM';
   ALTER SYSTEM SET effective_cache_size = '75% of RAM';
   ALTER SYSTEM SET work_mem = '256MB';
   ```

2. **Redis Memory Optimization**
   ```bash
   # Configure Redis for optimal memory usage
   redis-cli CONFIG SET maxmemory-policy allkeys-lru
   redis-cli CONFIG SET hash-max-ziplist-entries 512
   ```

### Index Optimization
```sql
-- Create additional indexes based on usage patterns
CREATE INDEX CONCURRENTLY idx_posts_trending 
ON posts(recent_likes_count DESC, recent_comments_count DESC, created_at DESC)
WHERE status = 'visible';

CREATE INDEX CONCURRENTLY idx_follows_active_users
ON follows(created_at) 
WHERE created_at > NOW() - INTERVAL '30 days';
```

### Cache Warming Strategy
```dart
class CacheWarming {
  static Future<void> warmUserCaches() async {
    final activeUsers = await getActiveUsers();
    
    for (final userId in activeUsers) {
      // Pre-generate timelines for active users
      await FanoutTimelineService.getUserTimeline(userId, forceRefresh: true);
      
      // Cache follow relationships
      await FollowService.getFollowers(userId);
      await FollowService.getFollowCounts(userId);
    }
  }
}
```

## Monitoring and Alerting

### Key Metrics to Monitor
1. **Database Response Times**
   - AlloyDB query response time (p95 < 100ms)
   - Redis cache response time (p95 < 5ms)
   - Firestore read/write latency

2. **Cache Performance**
   - Redis cache hit rate (target > 95%)
   - Memory usage (< 80% of allocated)
   - Eviction rate

3. **Data Consistency**
   - Synchronization lag between databases
   - Failed writes and rollbacks
   - Conflict resolution metrics

### Alert Thresholds
```yaml
alerts:
  - name: "High Database Latency"
    condition: "avg(database_query_duration) > 200ms"
    duration: "5m"
    
  - name: "Low Cache Hit Rate"
    condition: "cache_hit_rate < 90%"
    duration: "10m"
    
  - name: "Database Connection Failures"
    condition: "connection_errors > 10 per minute"
    duration: "2m"
```

## Security Considerations

### Connection Security
1. **Use SSL/TLS for all database connections**
2. **Implement connection pooling with authentication**
3. **Rotate database credentials regularly**
4. **Use private IP addresses for internal communication**

### Data Encryption
1. **Enable encryption at rest for AlloyDB**
2. **Use Redis AUTH for authentication**
3. **Encrypt sensitive data before storage**
4. **Implement field-level encryption for PII**

### Access Controls
1. **Implement RBAC for database access**
2. **Use service accounts with minimal permissions**
3. **Audit database access logs**
4. **Implement API rate limiting**

## Troubleshooting Guide

### Common Issues and Solutions

#### AlloyDB Connection Issues
```bash
# Check connection
psql -h $ALLOYDB_HOST -U $ALLOYDB_USER -d $ALLOYDB_DATABASE -c "SELECT 1;"

# Monitor active connections
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
```

#### Redis Connection Issues
```bash
# Test Redis connectivity
redis-cli -h $REDIS_HOST -p $REDIS_PORT ping

# Monitor Redis performance
redis-cli --latency -h $REDIS_HOST -p $REDIS_PORT
```

#### Firestore Performance Issues
```javascript
// Monitor Firestore usage
const usage = await admin.firestore().app.options.serviceAccountId;
console.log('Firestore usage:', usage);
```

### Performance Debugging
1. **Enable query logging in AlloyDB**
2. **Monitor Redis slow queries**
3. **Use Firestore profiling tools**
4. **Implement distributed tracing**