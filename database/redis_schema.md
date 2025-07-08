# Redis Schema Design for Timeline Caching and Fanout Processing

## Overview
Redis serves as the high-performance caching layer for timeline data, real-time counters, and fanout processing. This design optimizes for sub-millisecond read times and efficient timeline generation.

## Key Design Principles
1. **Fanout on Write**: Pre-generate timelines when posts are created
2. **Hybrid Push/Pull**: Push to active users, pull for inactive users
3. **TTL Management**: Automatic expiration for cache freshness
4. **Memory Optimization**: Efficient data structures and compression
5. **Scalable Counters**: Distributed counter patterns for high concurrency

## Data Structures and Key Patterns

### 1. User Timeline Caches
**Purpose**: Personal timeline data for fast retrieval

#### User Timeline (Sorted Set)
```redis
Key: timeline:{userId}
Type: ZSET (Sorted Set)
Score: timestamp (for chronological ordering)
Value: postId:{metadata}

# Example:
ZADD timeline:user123 1678901234 "post456:sports:2023-03-15:1234"
ZADD timeline:user123 1678901235 "post789:tech:2023-03-15:5678"

# TTL: 7 days
EXPIRE timeline:user123 604800
```

#### User Timeline Metadata
```redis
Key: timeline:meta:{userId}
Type: HASH
Fields:
- last_updated: timestamp
- total_items: count
- last_post_id: string
- timeline_version: integer

# Example:
HSET timeline:meta:user123 last_updated 1678901234
HSET timeline:meta:user123 total_items 150
HSET timeline:meta:user123 last_post_id "post789"
HSET timeline:meta:user123 timeline_version 2

# TTL: 7 days
EXPIRE timeline:meta:user123 604800
```

### 2. Global and Category Timelines
**Purpose**: Shared timeline data for discovery

#### Global Timeline
```redis
Key: global_timeline
Type: ZSET
Score: trend_score (calculated ranking)
Value: postId:{category}:{created_at}

# Example:
ZADD global_timeline 95.5 "post123:sports:1678901234"
ZADD global_timeline 87.2 "post456:tech:1678901235"

# TTL: 1 hour (refreshed frequently)
EXPIRE global_timeline 3600
```

#### Category Timelines
```redis
Key: timeline:category:{categoryName}
Type: ZSET
Score: trend_score or timestamp
Value: postId:{created_at}:{likes_count}

# Example:
ZADD timeline:category:sports 1678901234 "post123:1678901234:45"
ZADD timeline:category:tech 1678901235 "post456:1678901235:23"

# TTL: 2 hours
EXPIRE timeline:category:sports 7200
```

### 3. Real-time Counters
**Purpose**: High-performance counting for likes, views, comments

#### Post Counters (Hash)
```redis
Key: counter:{postId}
Type: HASH
Fields:
- likes: integer
- comments: integer  
- views: integer
- participants: integer
- recent_likes: integer (last 24h)
- recent_comments: integer (last 24h)
- recent_views: integer (last 24h)

# Example:
HSET counter:post123 likes 45
HSET counter:post123 comments 12
HSET counter:post123 views 1234
HSET counter:post123 recent_likes 8

# TTL: 30 days
EXPIRE counter:post123 2592000
```

#### Distributed Counter Shards
```redis
Key: counter:{postId}:shard:{shardId}
Type: STRING (integer)
Value: partial_count

# Example (for high-volume posts):
SET counter:post123:shard:0 15
SET counter:post123:shard:1 18  
SET counter:post123:shard:2 12

# Total likes = sum of all shards
# TTL: 30 days
EXPIRE counter:post123:shard:0 2592000
```

### 4. User Activity Tracking
**Purpose**: Track user interactions for personalization

#### User Like Status
```redis
Key: user_like:{userId}:{postId}
Type: STRING
Value: "1" (liked) or "0" (not liked)

# Example:
SET user_like:user123:post456 "1"

# TTL: 30 days
EXPIRE user_like:user123:post456 2592000
```

#### User Activity Stream
```redis
Key: activity:{userId}
Type: LIST (LPUSH for newest first)
Value: JSON activity data

# Example:
LPUSH activity:user123 '{"type":"like","postId":"post456","timestamp":1678901234}'
LPUSH activity:user123 '{"type":"comment","postId":"post789","timestamp":1678901235}'

# Keep only last 100 activities
LTRIM activity:user123 0 99

# TTL: 7 days
EXPIRE activity:user123 604800
```

### 5. Follow Relationships Cache
**Purpose**: Fast access to follow relationships

#### User Followers
```redis
Key: followers:{userId}
Type: SET
Value: follower_user_ids

# Example:
SADD followers:user123 user456 user789 user012

# TTL: 24 hours
EXPIRE followers:user123 86400
```

#### User Following
```redis
Key: following:{userId}  
Type: SET
Value: following_user_ids

# Example:
SADD following:user123 user345 user678 user901

# TTL: 24 hours
EXPIRE following:user123 86400
```

#### Follow Count Cache
```redis
Key: follow_count:{userId}
Type: HASH
Fields:
- followers: integer
- following: integer

# Example:
HSET follow_count:user123 followers 1250
HSET follow_count:user123 following 89

# TTL: 1 hour
EXPIRE follow_count:user123 3600
```

### 6. Fanout Processing Queues
**Purpose**: Manage timeline distribution to followers

#### Fanout Queue
```redis
Key: fanout_queue
Type: LIST
Value: JSON fanout job data

# Example:
LPUSH fanout_queue '{"postId":"post123","creatorId":"user456","followers":["user789","user012"],"timestamp":1678901234}'

# Process with BRPOP for blocking dequeue
BRPOP fanout_queue 30
```

#### Fanout Status Tracking
```redis
Key: fanout_status:{postId}
Type: HASH
Fields:
- status: "pending" | "processing" | "completed" | "failed"
- total_followers: integer
- processed_followers: integer
- started_at: timestamp
- completed_at: timestamp

# Example:
HSET fanout_status:post123 status "processing"
HSET fanout_status:post123 total_followers 1000
HSET fanout_status:post123 processed_followers 750

# TTL: 24 hours
EXPIRE fanout_status:post123 86400
```

### 7. Trending and Ranking Data
**Purpose**: Real-time trend calculations

#### Trending Posts (Sorted Set)
```redis
Key: trending:{period} # hourly, daily
Type: ZSET
Score: trend_score
Value: postId:{category}:{metrics}

# Example:
ZADD trending:hourly 95.5 "post123:sports:likes:45:comments:12"
ZADD trending:daily 87.2 "post456:tech:likes:234:comments:67"

# TTL: 25 hours for daily, 2 hours for hourly
EXPIRE trending:hourly 7200
EXPIRE trending:daily 90000
```

#### Category Rankings
```redis
Key: ranking:{category}:{period}
Type: ZSET  
Score: rank_score
Value: postId

# Example:
ZADD ranking:sports:daily 100 "post123"
ZADD ranking:sports:daily 95 "post456"

# TTL: 25 hours
EXPIRE ranking:sports:daily 90000
```

### 8. Session and Rate Limiting
**Purpose**: User session management and API rate limiting

#### User Sessions
```redis
Key: session:{sessionId}
Type: HASH
Fields:
- user_id: string
- created_at: timestamp
- last_activity: timestamp  
- device_info: JSON

# Example:
HSET session:abc123 user_id "user456"
HSET session:abc123 created_at 1678901234
HSET session:abc123 last_activity 1678901534

# TTL: 7 days (session expiration)
EXPIRE session:abc123 604800
```

#### Rate Limiting
```redis
Key: rate_limit:{userId}:{endpoint}
Type: STRING
Value: request_count

# Example:
SET rate_limit:user123:timeline_api 45

# TTL: 1 hour (sliding window)
EXPIRE rate_limit:user123:timeline_api 3600
```

### 9. Real-time Notifications
**Purpose**: Fast notification delivery

#### User Notification Queue
```redis
Key: notifications:{userId}
Type: LIST
Value: JSON notification data

# Example:
LPUSH notifications:user123 '{"type":"like","from":"user456","postId":"post789","timestamp":1678901234}'

# Keep only last 50 notifications
LTRIM notifications:user123 0 49

# TTL: 7 days
EXPIRE notifications:user123 604800
```

#### Push Notification Tokens
```redis
Key: push_tokens:{userId}
Type: SET
Value: device_tokens

# Example:
SADD push_tokens:user123 "fcm_token_abc123" "fcm_token_def456"

# TTL: 90 days
EXPIRE push_tokens:user123 7776000
```

### 10. Analytics and Metrics
**Purpose**: Real-time analytics data

#### Daily Active Users
```redis
Key: dau:{date} # YYYY-MM-DD
Type: SET
Value: user_ids

# Example:
SADD dau:2023-03-15 user123 user456 user789

# TTL: 30 days
EXPIRE dau:2023-03-15 2592000
```

#### Hourly Metrics
```redis
Key: metrics:hourly:{hour} # YYYY-MM-DD-HH
Type: HASH
Fields:
- posts_created: integer
- likes_added: integer
- comments_added: integer
- views_total: integer
- active_users: integer

# Example:
HSET metrics:hourly:2023-03-15-14 posts_created 45
HSET metrics:hourly:2023-03-15-14 likes_added 567

# TTL: 7 days
EXPIRE metrics:hourly:2023-03-15-14 604800
```

## Redis Configuration Optimizations

### Memory Optimization
```redis
# Use LZ4 compression for large values
CONFIG SET rdbcompression yes

# Optimize hash tables for memory
CONFIG SET hash-max-ziplist-entries 512
CONFIG SET hash-max-ziplist-value 64

# Set appropriate memory policy
CONFIG SET maxmemory-policy allkeys-lru

# Enable key expiration
CONFIG SET lazy-expire yes
```

### Performance Tuning
```redis
# Enable pipelining for batch operations
# Use connection pooling
# Implement read replicas for read-heavy workloads

# Cluster configuration for scaling
cluster-enabled yes
cluster-node-timeout 15000
cluster-config-file nodes.conf
```

## Implementation Patterns

### 1. Fanout Implementation
```python
async def fanout_post_to_followers(post_id: str, creator_id: str):
    # Get followers from cache or database
    followers = await redis.smembers(f"followers:{creator_id}")
    
    # Create fanout jobs in batches
    batch_size = 100
    for i in range(0, len(followers), batch_size):
        batch = followers[i:i + batch_size]
        job = {
            "postId": post_id,
            "creatorId": creator_id, 
            "followers": batch,
            "timestamp": int(time.time())
        }
        await redis.lpush("fanout_queue", json.dumps(job))
```

### 2. Timeline Generation
```python
async def get_user_timeline(user_id: str, limit: int = 20):
    # Try cache first
    cached_timeline = await redis.zrevrange(
        f"timeline:{user_id}", 0, limit-1, withscores=True
    )
    
    if cached_timeline:
        return parse_timeline_items(cached_timeline)
    
    # Fallback to database and cache result
    timeline = await generate_timeline_from_db(user_id, limit)
    await cache_user_timeline(user_id, timeline)
    return timeline
```

### 3. Counter Management
```python
async def increment_post_counter(post_id: str, counter_type: str):
    # Use distributed sharding for high-volume posts
    if await is_high_volume_post(post_id):
        shard_id = hash(post_id) % NUM_SHARDS
        await redis.incr(f"counter:{post_id}:shard:{shard_id}")
    else:
        await redis.hincrby(f"counter:{post_id}", counter_type, 1)
```

## Monitoring and Alerting

### Key Metrics to Monitor
1. **Memory Usage**: Monitor Redis memory consumption
2. **Hit Rate**: Cache hit/miss ratios
3. **Latency**: Response times for key operations
4. **Queue Lengths**: Fanout and processing queue sizes
5. **Expiration Rates**: TTL effectiveness

### Alert Thresholds
- Memory usage > 80%
- Cache hit rate < 95%
- Queue length > 10,000 items
- Response time > 5ms (p95)
- Error rate > 0.1%