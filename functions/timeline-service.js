// タイムライン読み込み専用サービス
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const redis = require('redis');

// Redis接続
const redisClient = redis.createClient({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT) || 6379
});

/**
 * ユーザータイムライン取得API
 * 読み込みパス: Redis (投稿IDリスト) → Firestore (投稿データ本体)
 */
exports.getUserTimeline = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { limit = 20, cursor = null } = data;
  const userId = context.auth.uid;

  try {
    // 1. Redis からタイムライン取得（投稿IDリスト）
    const timelineKey = `timeline:${userId}`;
    let postIds = [];
    
    try {
      await redisClient.connect();
      
      if (cursor) {
        // カーソルベースのページネーション
        const result = await redisClient.zRevRangeByScore(
          timelineKey,
          cursor,
          '-inf',
          {
            LIMIT: { offset: 0, count: limit }
          }
        );
        postIds = result;
      } else {
        // 最新投稿から取得
        const result = await redisClient.zRevRange(
          timelineKey,
          0,
          limit - 1
        );
        postIds = result;
      }
      
      await redisClient.disconnect();
    } catch (redisError) {
      console.warn('Redis error, falling back to Firestore:', redisError);
      // Redis障害時のフォールバック: Firestoreから直接取得
      return await getTimelineFromFirestore(userId, limit, cursor);
    }

    if (postIds.length === 0) {
      return {
        success: true,
        posts: [],
        hasMore: false,
        nextCursor: null
      };
    }

    // 2. Firestore から投稿データ本体を一括取得
    const posts = await getPostsByIds(postIds);
    
    // 3. Redis の順序を保持してソート
    const sortedPosts = postIds
      .map(id => posts.find(post => post.id === id))
      .filter(post => post && post.isActive); // アクティブな投稿のみ

    // 4. 次のページ用カーソル生成
    const nextCursor = sortedPosts.length >= limit 
      ? generateCursor(sortedPosts[sortedPosts.length - 1])
      : null;

    return {
      success: true,
      posts: sortedPosts,
      hasMore: nextCursor !== null,
      nextCursor,
      source: 'redis_cache'
    };

  } catch (error) {
    console.error('❌ Error getting user timeline:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get timeline');
  }
});

/**
 * グローバルタイムライン取得API
 */
exports.getGlobalTimeline = functions.https.onCall(async (data, context) => {
  const { limit = 20, cursor = null, category = null } = data;

  try {
    // 1. Redis からグローバルタイムライン取得
    const timelineKey = category ? `global_timeline:${category}` : 'global_timeline';
    let postIds = [];
    
    try {
      await redisClient.connect();
      
      if (cursor) {
        const result = await redisClient.zRevRangeByScore(
          timelineKey,
          cursor,
          '-inf',
          {
            LIMIT: { offset: 0, count: limit }
          }
        );
        postIds = result;
      } else {
        const result = await redisClient.zRevRange(
          timelineKey,
          0,
          limit - 1
        );
        postIds = result;
      }
      
      await redisClient.disconnect();
    } catch (redisError) {
      console.warn('Redis error, falling back to Firestore:', redisError);
      return await getGlobalTimelineFromFirestore(limit, cursor, category);
    }

    if (postIds.length === 0) {
      return {
        success: true,
        posts: [],
        hasMore: false,
        nextCursor: null
      };
    }

    // 2. Firestore から投稿データ本体を取得
    const posts = await getPostsByIds(postIds);
    
    const sortedPosts = postIds
      .map(id => posts.find(post => post.id === id))
      .filter(post => post && post.isActive);

    const nextCursor = sortedPosts.length >= limit 
      ? generateCursor(sortedPosts[sortedPosts.length - 1])
      : null;

    return {
      success: true,
      posts: sortedPosts,
      hasMore: nextCursor !== null,
      nextCursor,
      source: 'redis_cache'
    };

  } catch (error) {
    console.error('❌ Error getting global timeline:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get global timeline');
  }
});

/**
 * 投稿IDリストから投稿データを一括取得
 */
async function getPostsByIds(postIds) {
  if (postIds.length === 0) return [];
  
  const firestore = admin.firestore();
  const chunks = [];
  
  // Firestoreの制限（10件ずつ）でチャンク分割
  for (let i = 0; i < postIds.length; i += 10) {
    chunks.push(postIds.slice(i, i + 10));
  }
  
  const allPosts = [];
  
  for (const chunk of chunks) {
    const snapshot = await firestore
      .collection('counts')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    
    snapshot.docs.forEach(doc => {
      allPosts.push({
        id: doc.id,
        ...doc.data(),
        createdAt: doc.data().createdAt?.toDate(),
        eventDate: doc.data().eventDate?.toDate(),
        updatedAt: doc.data().updatedAt?.toDate()
      });
    });
  }
  
  return allPosts;
}

/**
 * Redis障害時のFirestoreフォールバック
 */
async function getTimelineFromFirestore(userId, limit, cursor) {
  const firestore = admin.firestore();
  
  // フォローしているユーザーの投稿を取得
  const followsSnapshot = await firestore
    .collection('follows')
    .where('followerId', '==', userId)
    .get();
  
  const followingIds = followsSnapshot.docs.map(doc => doc.data().followingId);
  followingIds.push(userId); // 自分の投稿も含める
  
  if (followingIds.length === 0) {
    return { success: true, posts: [], hasMore: false, nextCursor: null };
  }
  
  let query = firestore
    .collection('counts')
    .where('creatorId', 'in', followingIds.slice(0, 10)) // Firestoreの制限
    .where('isActive', '==', true)
    .orderBy('createdAt', 'desc')
    .limit(limit);
  
  if (cursor) {
    const cursorDoc = await firestore.collection('counts').doc(cursor).get();
    if (cursorDoc.exists) {
      query = query.startAfter(cursorDoc);
    }
  }
  
  const snapshot = await query.get();
  const posts = snapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
    createdAt: doc.data().createdAt?.toDate(),
    eventDate: doc.data().eventDate?.toDate(),
    updatedAt: doc.data().updatedAt?.toDate()
  }));
  
  return {
    success: true,
    posts,
    hasMore: posts.length >= limit,
    nextCursor: posts.length > 0 ? posts[posts.length - 1].id : null,
    source: 'firestore_fallback'
  };
}

/**
 * グローバルタイムラインのFirestoreフォールバック
 */
async function getGlobalTimelineFromFirestore(limit, cursor, category) {
  const firestore = admin.firestore();
  
  let query = firestore
    .collection('counts')
    .where('isActive', '==', true);
  
  if (category) {
    query = query.where('category', '==', category);
  }
  
  query = query
    .orderBy('createdAt', 'desc')
    .limit(limit);
  
  if (cursor) {
    const cursorDoc = await firestore.collection('counts').doc(cursor).get();
    if (cursorDoc.exists) {
      query = query.startAfter(cursorDoc);
    }
  }
  
  const snapshot = await query.get();
  const posts = snapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
    createdAt: doc.data().createdAt?.toDate(),
    eventDate: doc.data().eventDate?.toDate(),
    updatedAt: doc.data().updatedAt?.toDate()
  }));
  
  return {
    success: true,
    posts,
    hasMore: posts.length >= limit,
    nextCursor: posts.length > 0 ? posts[posts.length - 1].id : null,
    source: 'firestore_fallback'
  };
}

/**
 * カーソル生成
 */
function generateCursor(post) {
  return post.createdAt ? post.createdAt.getTime().toString() : post.id;
}