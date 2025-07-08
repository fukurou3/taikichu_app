// 投稿専用サービス - データ永続化とイベント発行のみ
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {PubSub} = require('@google-cloud/pubsub');

const pubsub = new PubSub();

/**
 * 投稿作成API
 * 責任: 投稿データの永続化 + イベント発行のみ
 */
exports.createPost = functions.https.onCall(async (data, context) => {
  // 認証チェック
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { eventName, description, eventDate, category, imageUrl } = data;
  
  if (!eventName || !eventDate) {
    throw new functions.https.HttpsError('invalid-argument', 'eventName and eventDate are required');
  }

  try {
    const userId = context.auth.uid;
    const postId = admin.firestore().collection('counts').doc().id;
    
    // 1. Firestoreに永続化（最優先）
    const postData = {
      eventName,
      description: description || '',
      eventDate: new Date(eventDate),
      category: category || 'other',
      imageUrl: imageUrl || null,
      creatorId: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 初期カウンター値
      participantsCount: 0,
      likesCount: 0,
      commentsCount: 0,
      viewsCount: 0,
      isActive: true
    };
    
    await admin.firestore()
      .collection('counts')
      .doc(postId)
      .set(postData);
    
    // 2. 成功後にイベント発行（非同期処理用）
    const event = {
      type: 'post_created',
      postId,
      userId,
      eventName,
      category,
      timestamp: new Date().toISOString(),
      metadata: {
        source: 'post_service',
        version: '1.0'
      }
    };
    
    await pubsub
      .topic('post-events')
      .publishMessage({
        data: Buffer.from(JSON.stringify(event)),
        attributes: {
          eventType: 'post_created',
          postId,
          userId
        }
      });
    
    console.log(`✅ Post created and event published: ${postId}`);
    
    return {
      success: true,
      postId,
      message: 'Post created successfully'
    };
    
  } catch (error) {
    console.error('❌ Error creating post:', error);
    throw new functions.https.HttpsError('internal', 'Failed to create post');
  }
});

/**
 * 投稿更新API
 */
exports.updatePost = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { postId, updates } = data;
  
  if (!postId) {
    throw new functions.https.HttpsError('invalid-argument', 'postId is required');
  }

  try {
    const userId = context.auth.uid;
    const postRef = admin.firestore().collection('counts').doc(postId);
    const postDoc = await postRef.get();
    
    if (!postDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Post not found');
    }
    
    const postData = postDoc.data();
    if (postData.creatorId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to update this post');
    }
    
    // 許可されたフィールドのみ更新
    const allowedFields = ['eventName', 'description', 'eventDate', 'category', 'imageUrl'];
    const updateData = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    
    for (const field of allowedFields) {
      if (updates[field] !== undefined) {
        updateData[field] = field === 'eventDate' ? new Date(updates[field]) : updates[field];
      }
    }
    
    await postRef.update(updateData);
    
    // 更新イベント発行
    const event = {
      type: 'post_updated',
      postId,
      userId,
      updatedFields: Object.keys(updateData),
      timestamp: new Date().toISOString(),
      metadata: {
        source: 'post_service',
        version: '1.0'
      }
    };
    
    await pubsub
      .topic('post-events')
      .publishMessage({
        data: Buffer.from(JSON.stringify(event)),
        attributes: {
          eventType: 'post_updated',
          postId,
          userId
        }
      });
    
    return {
      success: true,
      postId,
      message: 'Post updated successfully'
    };
    
  } catch (error) {
    console.error('❌ Error updating post:', error);
    if (error.code) throw error;
    throw new functions.https.HttpsError('internal', 'Failed to update post');
  }
});

/**
 * 投稿削除API
 */
exports.deletePost = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { postId } = data;
  
  if (!postId) {
    throw new functions.https.HttpsError('invalid-argument', 'postId is required');
  }

  try {
    const userId = context.auth.uid;
    const postRef = admin.firestore().collection('counts').doc(postId);
    const postDoc = await postRef.get();
    
    if (!postDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Post not found');
    }
    
    const postData = postDoc.data();
    if (postData.creatorId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to delete this post');
    }
    
    // ソフト削除
    await postRef.update({
      isActive: false,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    // 削除イベント発行
    const event = {
      type: 'post_deleted',
      postId,
      userId,
      timestamp: new Date().toISOString(),
      metadata: {
        source: 'post_service',
        version: '1.0'
      }
    };
    
    await pubsub
      .topic('post-events')
      .publishMessage({
        data: Buffer.from(JSON.stringify(event)),
        attributes: {
          eventType: 'post_deleted',
          postId,
          userId
        }
      });
    
    return {
      success: true,
      postId,
      message: 'Post deleted successfully'
    };
    
  } catch (error) {
    console.error('❌ Error deleting post:', error);
    if (error.code) throw error;
    throw new functions.https.HttpsError('internal', 'Failed to delete post');
  }
});