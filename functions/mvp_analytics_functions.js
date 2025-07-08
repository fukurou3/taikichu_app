// 統一イベント処理用 Cloud Functions
// 
// 🎯 目的: 全てのクライアントイベントを統一HTTPエンドポイントで受信
// 💰 効果: 書き込み経路の統一とFirestoreトリガー依存の排除

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {PubSub} = require('@google-cloud/pubsub');

admin.initializeApp();
const pubsub = new PubSub();
const TOPIC_NAME = 'analytics-events';

// サポートされるイベントタイプの定義
const SUPPORTED_EVENT_TYPES = {
  'countdown_created': { requiresAuth: true, requiredFields: ['countdownId', 'eventName', 'eventDate'] },
  'like_added': { requiresAuth: true, requiredFields: ['countdownId', 'userId'] },
  'like_removed': { requiresAuth: true, requiredFields: ['countdownId', 'userId'] },
  'participation_added': { requiresAuth: true, requiredFields: ['countdownId', 'userId'] },
  'participation_removed': { requiresAuth: true, requiredFields: ['countdownId', 'userId'] },
  'comment_added': { requiresAuth: true, requiredFields: ['countdownId', 'userId', 'commentId'] },
  'view': { requiresAuth: true, requiredFields: ['countdownId', 'userId'] },
  'report_created': { requiresAuth: true, requiredFields: ['targetType', 'targetId', 'reportType'] },
  'moderation_action': { requiresAuth: true, requiredFields: ['actionType', 'targetId', 'moderatorId'] }
};

/**
 * イベントバリデーション関数
 */
function validateEvent(eventType, eventData, context) {
  const eventConfig = SUPPORTED_EVENT_TYPES[eventType];
  
  if (!eventConfig) {
    throw new functions.https.HttpsError('invalid-argument', `Unsupported event type: ${eventType}`);
  }
  
  // 認証チェック
  if (eventConfig.requiresAuth && !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  
  // 必須フィールドチェック
  for (const field of eventConfig.requiredFields) {
    if (!eventData[field]) {
      throw new functions.https.HttpsError('invalid-argument', `Missing required field: ${field}`);
    }
  }
  
  // ユーザーIDの整合性チェック
  if (eventData.userId && context.auth && eventData.userId !== context.auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'User ID mismatch');
  }
  
  return true;
}

/**
 * 統一イベントハンドラー (HTTP Trigger)
 * 
 * 全てのクライアントイベントを受信し、Pub/Subに転送
 * 書き込み経路: クライアント → HTTP → Pub/Sub → Analytics Service
 */
exports.unifiedEventHandler = functions.https.onCall(async (data, context) => {
  const startTime = Date.now();
  
  try {
    const { eventType, eventData, metadata = {} } = data;
    
    if (!eventType || !eventData) {
      throw new functions.https.HttpsError('invalid-argument', 'eventType and eventData are required');
    }
    
    // イベントバリデーション
    validateEvent(eventType, eventData, context);
    
    // 統一イベントメッセージ作成
    const unifiedEvent = {
      type: eventType,
      data: eventData,
      userId: context.auth?.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        source: 'unified_http_handler',
        version: '2.0',
        userAgent: metadata.userAgent || 'unknown',
        clientVersion: metadata.clientVersion || 'unknown',
        ...metadata
      }
    };
    
    // Pub/Subに発行
    const messageId = await pubsub
      .topic(TOPIC_NAME)
      .publishMessage({
        data: Buffer.from(JSON.stringify(unifiedEvent)),
        attributes: {
          eventType: eventType,
          userId: context.auth?.uid || 'anonymous',
          timestamp: new Date().toISOString()
        }
      });
    
    const executionTime = Date.now() - startTime;
    console.log(`✅ Unified event published: ${eventType} - ${messageId} (${executionTime}ms)`);
    
    return { 
      success: true, 
      messageId, 
      executionTime,
      eventType,
      message: 'Event published successfully through unified handler'
    };
    
  } catch (error) {
    const executionTime = Date.now() - startTime;
    console.error(`❌ Error in unified event handler (${executionTime}ms):`, error);
    
    if (error.code) {
      throw error; // Firebase関数エラーをそのまま投げる
    }
    
    throw new functions.https.HttpsError('internal', 'Failed to process event');
  }
});

/**
 * バッチイベント処理 (HTTP Trigger)
 * 
 * 複数のイベントを一度に処理するためのエンドポイント
 */
exports.batchEventHandler = functions.https.onCall(async (data, context) => {
  const startTime = Date.now();
  
  try {
    const { events, metadata = {} } = data;
    
    if (!Array.isArray(events) || events.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'events array is required');
    }
    
    if (events.length > 50) {
      throw new functions.https.HttpsError('invalid-argument', 'Maximum 50 events per batch');
    }
    
    const results = [];
    const publishPromises = [];
    
    for (const [index, eventItem] of events.entries()) {
      try {
        const { eventType, eventData } = eventItem;
        
        if (!eventType || !eventData) {
          results.push({ index, success: false, error: 'Missing eventType or eventData' });
          continue;
        }
        
        // イベントバリデーション
        validateEvent(eventType, eventData, context);
        
        // バッチイベントメッセージ作成
        const batchEvent = {
          type: eventType,
          data: eventData,
          userId: context.auth?.uid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            source: 'batch_http_handler',
            version: '2.0',
            batchIndex: index,
            batchSize: events.length,
            ...metadata
          }
        };
        
        // 非同期でPub/Sub発行
        const publishPromise = pubsub
          .topic(TOPIC_NAME)
          .publishMessage({
            data: Buffer.from(JSON.stringify(batchEvent)),
            attributes: {
              eventType: eventType,
              userId: context.auth?.uid || 'anonymous',
              batchIndex: index.toString(),
              timestamp: new Date().toISOString()
            }
          })
          .then(messageId => {
            results.push({ index, success: true, messageId, eventType });
          })
          .catch(error => {
            results.push({ index, success: false, error: error.message, eventType });
          });
        
        publishPromises.push(publishPromise);
        
      } catch (error) {
        results.push({ index, success: false, error: error.message });
      }
    }
    
    // 全てのPub/Sub発行を待機
    await Promise.all(publishPromises);
    
    const executionTime = Date.now() - startTime;
    const successCount = results.filter(r => r.success).length;
    
    console.log(`✅ Batch events processed: ${successCount}/${events.length} successful (${executionTime}ms)`);
    
    return {
      success: true,
      executionTime,
      totalEvents: events.length,
      successfulEvents: successCount,
      results: results
    };
    
  } catch (error) {
    const executionTime = Date.now() - startTime;
    console.error(`❌ Error in batch event handler (${executionTime}ms):`, error);
    
    if (error.code) {
      throw error;
    }
    
    throw new functions.https.HttpsError('internal', 'Failed to process batch events');
  }
});

// 従来のFirestoreトリガーは統一HTTPハンドラーに置き換え済み
// 以下のFirestoreトリガーは廃止予定:
// - onLikeCreate/onLikeDelete
// - onParticipationCreate/onParticipationDelete  
// - onCommentCreate
//
// 新しいフロー:
// クライアント → unifiedEventHandler → Pub/Sub → Analytics Service

/**
 * 後方互換性のためのビューイベントエンドポイント
 * 
 * 注意: このエンドポイントは廃止予定です
 * 新しいクライアントは unifiedEventHandler を使用してください
 */
exports.publishViewEvent = functions.https.onCall(async (data, context) => {
  console.warn('⚠️ publishViewEvent is deprecated. Use unifiedEventHandler instead.');
  
  // 統一ハンドラーに転送
  const unifiedData = {
    eventType: 'view',
    eventData: {
      countdownId: data.countdownId,
      userId: context.auth?.uid
    },
    metadata: {
      source: 'legacy_view_endpoint',
      ...data.metadata
    }
  };
  
  return exports.unifiedEventHandler(unifiedData, context);
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
 * firebase deploy --only functions:unifiedEventHandler,functions:batchEventHandler,functions:publishViewEvent,functions:getPubSubHealth
 * 
 * 移行手順:
 * 1. 新しいHTTPトリガーをデプロイ
 * 2. クライアントアプリを更新して統一ハンドラーを使用
 * 3. 古いFirestoreトリガーを削除
 * 4. publishViewEventを削除（後方互換性期間後）
 */