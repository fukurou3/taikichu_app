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

