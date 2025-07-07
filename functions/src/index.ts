import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Firebase Admin SDKを初期化
admin.initializeApp();

/**
 * 統一パイプライン移行完了後のCloud Functions
 * 
 * ⚠️ 重要：統一パイプライン導入により、以下の機能は廃止されました：
 * - 直接的なカウンター更新（onCommentCreate, onLikeCreate, onViewCreate等）
 * - 分散カウンター処理（incrementDistributedCounter等）
 * - Firestoreトリガーによるランキング更新（updateTrendRankings等）
 * 
 * 🚀 新システム：
 * - 全操作はUnifiedAnalyticsService → Pub/Sub → Cloud Run で処理
 * - カウンター値はRedisで管理
 * - ランキングはCloud Runで計算・更新
 */

/**
 * システム健康状態の確認用エンドポイント
 */
export const healthCheck = functions.https.onRequest(async (req, res) => {
  try {
    res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: "unified-pipeline-v1.0",
      message: "統一パイプライン対応版 - レガシー機能は無効化済み"
    });
  } catch (error) {
    res.status(500).json({
      status: "error",
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});

/**
 * 緊急時のデバッグ情報取得
 */
export const getSystemInfo = functions.https.onRequest(async (req, res) => {
  try {
    const info = {
      timestamp: new Date().toISOString(),
      pipeline: "unified",
      status: "active",
      components: {
        analytics_service: "https://analytics-service-694414843228.asia-northeast1.run.app",
        pubsub_topic: "analytics-events",
        redis_cache: "enabled",
        firestore_direct_writes: "disabled"
      },
      migration: {
        legacy_functions: "removed",
        distributed_counters: "migrated_to_redis",
        trend_rankings: "computed_in_cloud_run"
      }
    };

    res.status(200).json(info);
  } catch (error) {
    res.status(500).json({
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});

// 以下のコメントアウトされた関数は統一パイプライン移行により不要になりました
// 参考用に残していますが、実際には削除予定です

/*
// ❌ 廃止済み：コメント投稿時のトリガー関数
// 理由：統一パイプラインでPub/Sub → Cloud Run経由で処理
export const onCommentCreate = functions.firestore
  .document("comments/{commentId}")
  .onCreate(async (snapshot, context) => {
    // 統一パイプラインに移行済み - この関数は実行されません
  });

// ❌ 廃止済み：いいね作成時のトリガー関数
// 理由：統一パイプラインでPub/Sub → Cloud Run経由で処理
export const onLikeCreate = functions.firestore
  .document("countdownLikes/{likeId}")
  .onCreate(async (snapshot, context) => {
    // 統一パイプラインに移行済み - この関数は実行されません
  });

// ❌ 廃止済み：閲覧数トラッキングのトリガー関数
// 理由：統一パイプラインでPub/Sub → Cloud Run経由で処理
export const onViewCreate = functions.firestore
  .document("views/{viewId}")
  .onCreate(async (snapshot, context) => {
    // 統一パイプラインに移行済み - この関数は実行されません
  });

// ❌ 廃止済み：トレンドランキング更新関数
// 理由：Cloud Runで高速処理・Redis管理に移行
export const updateTrendRankings = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    // 統一パイプラインに移行済み - この関数は実行されません
  });

// ❌ 廃止済み：分散カウンター実装
// 理由：Redisによる高速カウンター管理に移行
export const incrementDistributedCounter = functions.https.onCall(async (data, context) => {
  // 統一パイプラインに移行済み - この関数は実行されません
});
*/