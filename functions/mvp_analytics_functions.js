// MVP分析基盤用 Cloud Functions
// 
// 🎯 目的: Firestoreの直接更新をやめ、Pub/Subイベント発行に専念
// 💰 効果: 実行時間とコストを最小化

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {PubSub} = require('@google-cloud/pubsub');

admin.initializeApp();
const pubsub = new PubSub();
const TOPIC_NAME = 'analytics-events';

/**
 * いいね作成時のイベント発行
 * 
 * 従来: Firestoreカウンター直接更新（重い処理）
 * 新版: Pub/Subイベント発行のみ（軽量・高速）
 */
exports.onLikeCreate = functions.firestore
  .document('likes/{likeId}')
  .onCreate(async (snap, context) => {
    const startTime = Date.now();
    
    try {
      const likeData = snap.data();
      const likeId = context.params.likeId;
      
      // 🚀 シンプルなイベントメッセージ作成
      const event = {
        type: 'like_added',
        countdownId: likeData.countdownId,
        userId: likeData.userId,
        likeId: likeId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          source: 'firestore_trigger',
          version: '1.0'
        }
      };
      
      // 📨 Pub/Sub に即座送信（軽量処理）
      const messageId = await pubsub
        .topic(TOPIC_NAME)
        .publishMessage({
          data: Buffer.from(JSON.stringify(event)),
          attributes: {
            eventType: 'like_added',
            countdownId: likeData.countdownId,
            userId: likeData.userId
          }
        });
      
      const executionTime = Date.now() - startTime;
      console.log(`✅ Like event published: ${messageId} (${executionTime}ms)`);
      
      return { success: true, messageId, executionTime };
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      console.error(`❌ Error publishing like event (${executionTime}ms):`, error);
      // エラーでも処理は継続（分析は副次的）
    }
  });

/**
 * いいね削除時のイベント発行
 */
exports.onLikeDelete = functions.firestore
  .document('likes/{likeId}')
  .onDelete(async (snap, context) => {
    const startTime = Date.now();
    
    try {
      const likeData = snap.data();
      const likeId = context.params.likeId;
      
      const event = {
        type: 'like_removed',
        countdownId: likeData.countdownId,
        userId: likeData.userId,
        likeId: likeId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          source: 'firestore_trigger',
          version: '1.0'
        }
      };
      
      const messageId = await pubsub
        .topic(TOPIC_NAME)
        .publishMessage({
          data: Buffer.from(JSON.stringify(event)),
          attributes: {
            eventType: 'like_removed',
            countdownId: likeData.countdownId,
            userId: likeData.userId
          }
        });
      
      const executionTime = Date.now() - startTime;
      console.log(`✅ Like removal event published: ${messageId} (${executionTime}ms)`);
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      console.error(`❌ Error publishing like removal event (${executionTime}ms):`, error);
    }
  });

/**
 * 参加作成時のイベント発行
 */
exports.onParticipationCreate = functions.firestore
  .document('participants/{participantId}')
  .onCreate(async (snap, context) => {
    const startTime = Date.now();
    
    try {
      const participantData = snap.data();
      const participantId = context.params.participantId;
      
      const event = {
        type: 'participation_added',
        countdownId: participantData.countdownId,
        userId: participantData.userId,
        participantId: participantId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          source: 'firestore_trigger',
          version: '1.0'
        }
      };
      
      const messageId = await pubsub
        .topic(TOPIC_NAME)
        .publishMessage({
          data: Buffer.from(JSON.stringify(event)),
          attributes: {
            eventType: 'participation_added',
            countdownId: participantData.countdownId,
            userId: participantData.userId
          }
        });
      
      const executionTime = Date.now() - startTime;
      console.log(`✅ Participation event published: ${messageId} (${executionTime}ms)`);
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      console.error(`❌ Error publishing participation event (${executionTime}ms):`, error);
    }
  });

/**
 * 参加削除時のイベント発行
 */
exports.onParticipationDelete = functions.firestore
  .document('participants/{participantId}')
  .onDelete(async (snap, context) => {
    const startTime = Date.now();
    
    try {
      const participantData = snap.data();
      const participantId = context.params.participantId;
      
      const event = {
        type: 'participation_removed',
        countdownId: participantData.countdownId,
        userId: participantData.userId,
        participantId: participantId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          source: 'firestore_trigger',
          version: '1.0'
        }
      };
      
      const messageId = await pubsub
        .topic(TOPIC_NAME)
        .publishMessage({
          data: Buffer.from(JSON.stringify(event)),
          attributes: {
            eventType: 'participation_removed',
            countdownId: participantData.countdownId,
            userId: participantData.userId
          }
        });
      
      const executionTime = Date.now() - startTime;
      console.log(`✅ Participation removal event published: ${messageId} (${executionTime}ms)`);
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      console.error(`❌ Error publishing participation removal event (${executionTime}ms):`, error);
    }
  });

/**
 * コメント作成時のイベント発行
 */
exports.onCommentCreate = functions.firestore
  .document('comments/{commentId}')
  .onCreate(async (snap, context) => {
    const startTime = Date.now();
    
    try {
      const commentData = snap.data();
      const commentId = context.params.commentId;
      
      const event = {
        type: 'comment_added',
        countdownId: commentData.countdownId,
        userId: commentData.authorId,
        commentId: commentId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          source: 'firestore_trigger',
          version: '1.0',
          commentLength: commentData.content?.length || 0
        }
      };
      
      const messageId = await pubsub
        .topic(TOPIC_NAME)
        .publishMessage({
          data: Buffer.from(JSON.stringify(event)),
          attributes: {
            eventType: 'comment_added',
            countdownId: commentData.countdownId,
            userId: commentData.authorId
          }
        });
      
      const executionTime = Date.now() - startTime;
      console.log(`✅ Comment event published: ${messageId} (${executionTime}ms)`);
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      console.error(`❌ Error publishing comment event (${executionTime}ms):`, error);
    }
  });

/**
 * 閲覧イベントの直接発行（HTTP trigger）
 * 
 * クライアントから直接呼び出される軽量エンドポイント
 */
exports.publishViewEvent = functions.https.onCall(async (data, context) => {
  const startTime = Date.now();
  
  try {
    // 認証チェック
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }
    
    const { countdownId, metadata = {} } = data;
    
    if (!countdownId) {
      throw new functions.https.HttpsError('invalid-argument', 'countdownId is required');
    }
    
    const event = {
      type: 'view',
      countdownId: countdownId,
      userId: context.auth.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        source: 'client_call',
        version: '1.0',
        userAgent: metadata.userAgent || 'unknown',
        ...metadata
      }
    };
    
    const messageId = await pubsub
      .topic(TOPIC_NAME)
      .publishMessage({
        data: Buffer.from(JSON.stringify(event)),
        attributes: {
          eventType: 'view',
          countdownId: countdownId,
          userId: context.auth.uid
        }
      });
    
    const executionTime = Date.now() - startTime;
    console.log(`✅ View event published: ${messageId} (${executionTime}ms)`);
    
    return { 
      success: true, 
      messageId, 
      executionTime,
      message: 'View event published successfully' 
    };
    
  } catch (error) {
    const executionTime = Date.now() - startTime;
    console.error(`❌ Error publishing view event (${executionTime}ms):`, error);
    
    if (error.code) {
      throw error; // Firebase関数エラーをそのまま投げる
    }
    
    throw new functions.https.HttpsError('internal', 'Failed to publish view event');
  }
});

/**
 * システム監視: Pub/Sub の健康状態確認
 */
exports.getPubSubHealth = functions.https.onRequest(async (req, res) => {
  try {
    // トピックの存在確認
    const [topicExists] = await pubsub.topic(TOPIC_NAME).exists();
    
    // サブスクリプションの確認
    const [subscriptions] = await pubsub.topic(TOPIC_NAME).getSubscriptions();
    
    // 最近のメッセージ統計（簡易版）
    const health = {
      status: topicExists ? 'healthy' : 'error',
      topic: {
        name: TOPIC_NAME,
        exists: topicExists
      },
      subscriptions: subscriptions.map(sub => ({
        name: sub.name,
        exists: true
      })),
      timestamp: new Date().toISOString(),
      version: '1.0'
    };
    
    res.json(health);
    
  } catch (error) {
    console.error('Error checking Pub/Sub health:', error);
    res.status(500).json({
      status: 'error',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * デプロイコマンド:
 * 
 * firebase deploy --only functions:onLikeCreate,functions:onLikeDelete,functions:onParticipationCreate,functions:onParticipationDelete,functions:onCommentCreate,functions:publishViewEvent,functions:getPubSubHealth
 */