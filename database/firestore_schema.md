# Firestore Schema Design for Timeline and Notification Data

## Overview
Firestore is optimized for real-time data, document-based storage with excellent scalability for read-heavy workloads. This schema focuses on timeline data, notifications, and real-time activity streams.

## Collection Structure

### 1. `user_timelines` Collection
**Purpose**: Personal timelines for each user with cached timeline items
**Document ID**: `{userId}`

```javascript
{
  "userId": "string",
  "lastUpdated": "timestamp",
  "timelineItems": [
    {
      "postId": "string",
      "eventName": "string", 
      "creatorId": "string",
      "creatorUsername": "string",
      "eventDate": "timestamp",
      "category": "string",
      "imageUrl": "string?",
      "likesCount": "number",
      "commentsCount": "number",
      "participantsCount": "number",
      "addedAt": "timestamp", // When added to timeline
      "score": "number" // For timeline ranking
    }
  ],
  "metadata": {
    "totalItems": "number",
    "lastPostTimestamp": "timestamp",
    "categories": ["string"], // User's followed categories
    "isOptimized": "boolean" // Whether timeline has been optimized
  }
}
```

### 2. `global_timelines` Collection  
**Purpose**: Category-specific and global timeline caching
**Document ID**: `global` | `category_{categoryName}`

```javascript
{
  "type": "global" | "category",
  "categoryName": "string?", // null for global timeline
  "lastUpdated": "timestamp",
  "timelineItems": [
    {
      "postId": "string",
      "eventName": "string",
      "creatorId": "string", 
      "creatorUsername": "string",
      "eventDate": "timestamp",
      "category": "string",
      "imageUrl": "string?",
      "likesCount": "number",
      "commentsCount": "number", 
      "participantsCount": "number",
      "recentLikesCount": "number", // Last 24h
      "recentCommentsCount": "number", // Last 24h
      "trendScore": "number",
      "createdAt": "timestamp",
      "rank": "number" // Position in timeline
    }
  ],
  "metadata": {
    "totalPosts": "number",
    "lastRefresh": "timestamp",
    "refreshInterval": "number", // minutes
    "maxItems": "number" // max timeline items to keep
  }
}
```

### 3. `notifications` Collection
**Purpose**: User notifications for real-time updates
**Document ID**: Auto-generated

```javascript
{
  "userId": "string", // Recipient
  "type": "string", // "like", "comment", "follow", "event_reminder", "admin_action"
  "title": "string",
  "body": "string", 
  "data": {
    // Type-specific data
    "postId": "string?",
    "commentId": "string?", 
    "fromUserId": "string?",
    "fromUsername": "string?",
    "eventDate": "timestamp?",
    "actionType": "string?" // For admin notifications
  },
  "isRead": "boolean",
  "isDelivered": "boolean", 
  "priority": "string", // "high", "medium", "low"
  "createdAt": "timestamp",
  "readAt": "timestamp?",
  "expiresAt": "timestamp?" // Auto-delete after this time
}
```

### 4. `real_time_activities` Collection
**Purpose**: Live activity streams for real-time updates
**Document ID**: `{userId}` 

```javascript
{
  "userId": "string",
  "lastActivity": "timestamp",
  "activities": [
    {
      "id": "string",
      "type": "string", // "post_created", "like_added", "comment_added", "follow_added"
      "postId": "string?",
      "targetUserId": "string?",
      "message": "string", // Formatted activity message
      "timestamp": "timestamp",
      "metadata": {
        "postTitle": "string?",
        "category": "string?",
        "isPublic": "boolean"
      }
    }
  ],
  "settings": {
    "maxActivities": "number", // Default 100
    "autoCleanup": "boolean",
    "retentionDays": "number" // Default 30
  }
}
```

### 5. `trending_data` Collection
**Purpose**: Real-time trending calculations and rankings
**Document ID**: `daily_{YYYY-MM-DD}` | `hourly_{YYYY-MM-DD-HH}`

```javascript
{
  "period": "string", // "daily" | "hourly"
  "date": "string", // ISO date string
  "lastCalculated": "timestamp",
  "trendingPosts": [
    {
      "postId": "string",
      "eventName": "string",
      "category": "string",
      "creatorId": "string",
      "creatorUsername": "string",
      "trendScore": "number",
      "rank": "number",
      "metrics": {
        "likes": "number",
        "comments": "number", 
        "views": "number",
        "participants": "number",
        "recentLikes": "number", // Period-specific
        "recentComments": "number",
        "recentViews": "number"
      },
      "growth": {
        "likesGrowth": "number", // % change
        "commentsGrowth": "number",
        "viewsGrowth": "number"
      }
    }
  ],
  "categories": {
    "sports": ["postId1", "postId2"], // Top posts by category
    "entertainment": ["postId3", "postId4"],
    "technology": ["postId5", "postId6"]
  },
  "metadata": {
    "totalPosts": "number",
    "calculationTime": "number", // milliseconds
    "algorithm": "string" // Algorithm version used
  }
}
```

### 6. `user_feed_cache` Collection
**Purpose**: Cached personalized feeds based on user preferences
**Document ID**: `{userId}`

```javascript
{
  "userId": "string",
  "lastGenerated": "timestamp",
  "expiresAt": "timestamp", // Cache expiration
  "feedItems": [
    {
      "postId": "string",
      "relevanceScore": "number", // Personalization score
      "source": "string", // "following", "trending", "category", "recommendation"
      "addedAt": "timestamp",
      "seenBy": "boolean", // Whether user has seen this item
      "interactedWith": "boolean" // Whether user interacted
    }
  ],
  "userPreferences": {
    "followedCategories": ["string"],
    "blockedCategories": ["string"], 
    "preferredEventTypes": ["string"],
    "feedMix": {
      "followingWeight": "number", // 0-1
      "trendingWeight": "number", // 0-1
      "categoryWeight": "number", // 0-1
      "recommendationWeight": "number" // 0-1
    }
  },
  "metrics": {
    "totalItems": "number",
    "seenItems": "number",
    "interactionRate": "number",
    "lastInteraction": "timestamp"
  }
}
```

### 7. `live_events` Collection
**Purpose**: Real-time event updates and live countdown status
**Document ID**: `{postId}`

```javascript
{
  "postId": "string",
  "eventName": "string", 
  "eventDate": "timestamp",
  "status": "string", // "upcoming", "live", "ended"
  "isLive": "boolean",
  "liveData": {
    "currentParticipants": "number",
    "liveViewers": "number", // Real-time viewers
    "liveLikes": "number", // Real-time likes
    "liveComments": "number", // Real-time comments
    "lastActivity": "timestamp"
  },
  "countdownData": {
    "timeRemaining": "number", // seconds
    "daysLeft": "number",
    "hoursLeft": "number", 
    "minutesLeft": "number",
    "secondsLeft": "number"
  },
  "notifications": {
    "remindersSent": ["timestamp"], // When reminders were sent
    "nextReminder": "timestamp?", // Next scheduled reminder
    "subscribers": ["userId"] // Users who want reminders
  },
  "updatedAt": "timestamp"
}
```

### 8. `user_engagement` Collection  
**Purpose**: Track user engagement patterns for recommendations
**Document ID**: `{userId}`

```javascript
{
  "userId": "string",
  "lastUpdated": "timestamp",
  "engagementPattern": {
    "activeHours": ["number"], // Hours when user is most active (0-23)
    "activeDays": ["string"], // Days when user is most active
    "sessionDuration": "number", // Average session duration in minutes
    "interactionRate": "number", // Likes+comments per view
    "preferredCategories": {
      "sports": "number", // Engagement score 0-1
      "entertainment": "number",
      "technology": "number",
      "education": "number"
    }
  },
  "recentActivity": [
    {
      "action": "string", // "view", "like", "comment", "share"
      "postId": "string",
      "category": "string",
      "timestamp": "timestamp",
      "duration": "number?" // For view actions
    }
  ],
  "recommendations": {
    "suggestedCategories": ["string"],
    "suggestedUsers": ["userId"],
    "lastUpdated": "timestamp"
  }
}
```

## Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // User timelines - users can only access their own timeline
    match /user_timelines/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Global timelines - read-only for authenticated users
    match /global_timelines/{timelineId} {
      allow read: if request.auth != null;
      allow write: if false; // Only server-side updates
    }
    
    // Notifications - users can only access their own notifications
    match /notifications/{notificationId} {
      allow read, write: if request.auth != null && 
        request.auth.uid == resource.data.userId;
    }
    
    // Real-time activities - users can only access their own activities
    match /real_time_activities/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Trending data - read-only for authenticated users
    match /trending_data/{trendId} {
      allow read: if request.auth != null;
      allow write: if false; // Only server-side updates
    }
    
    // User feed cache - users can only access their own feed
    match /user_feed_cache/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Live events - read-only for authenticated users
    match /live_events/{postId} {
      allow read: if request.auth != null;
      allow write: if false; // Only server-side updates
    }
    
    // User engagement - users can only access their own engagement data
    match /user_engagement/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Indexing Strategy

### Composite Indexes Needed:

1. **notifications**: `(userId, createdAt desc)`
2. **notifications**: `(userId, isRead, createdAt desc)`
3. **real_time_activities**: `(userId, timestamp desc)`
4. **trending_data**: `(period, date desc)`
5. **user_feed_cache**: `(userId, lastGenerated desc)`
6. **live_events**: `(status, eventDate asc)`
7. **user_engagement**: `(userId, lastUpdated desc)`

### Collection Group Queries:
- None needed for this schema design

## Data Lifecycle Management

### TTL (Time To Live) Policies:
1. **notifications**: Auto-delete after 30 days
2. **real_time_activities**: Auto-delete after 30 days  
3. **trending_data**: Keep last 30 daily records, 72 hourly records
4. **user_feed_cache**: Auto-refresh every 2 hours
5. **live_events**: Delete 24 hours after event ends

### Optimization Strategies:
1. **Batch Operations**: Use batch writes for timeline updates
2. **Pagination**: Implement cursor-based pagination for large collections
3. **Offline Support**: Use Firestore offline persistence for mobile apps
4. **Real-time Listeners**: Minimize real-time listeners to essential data only
5. **Data Denormalization**: Store frequently accessed data redundantly for performance

## Integration with Redis and AlloyDB

### Data Flow:
1. **Write Path**: AlloyDB → Cloud Functions → Firestore + Redis
2. **Read Path**: App → Redis → Firestore → AlloyDB (fallback)
3. **Real-time**: App ↔ Firestore real-time listeners
4. **Analytics**: Firestore → Cloud Functions → Analytics processing

### Consistency Strategy:
- **Eventually Consistent**: Timeline data across systems
- **Strong Consistency**: Critical user data in AlloyDB
- **Real-time Updates**: Firestore for live data, Redis for caching