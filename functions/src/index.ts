import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Firebase Admin SDKを初期化
admin.initializeApp();

const db = admin.firestore();

/**
 * コメント投稿時のトリガー関数
 * コメントが作成されたときに、対応するカウントダウンのcommentsCountを更新
 */
export const onCommentCreate = functions.firestore
  .document("comments/{commentId}")
  .onCreate(async (snapshot, context) => {
    try {
      const commentData = snapshot.data();
      const countdownId = commentData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in comment data");
        return;
      }

      // カウントダウンのcommentsCountを+1
      await db.collection("counts").doc(countdownId).update({
        commentsCount: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Updated commentsCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error updating comments count:", error);
    }
  });

/**
 * コメント削除時のトリガー関数
 * コメントが削除されたときに、対応するカウントダウンのcommentsCountを更新
 */
export const onCommentDelete = functions.firestore
  .document("comments/{commentId}")
  .onDelete(async (snapshot, context) => {
    try {
      const commentData = snapshot.data();
      const countdownId = commentData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in comment data");
        return;
      }

      // カウントダウンのcommentsCountを-1
      await db.collection("counts").doc(countdownId).update({
        commentsCount: admin.firestore.FieldValue.increment(-1),
      });

      console.log(`Decremented commentsCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error decrementing comments count:", error);
    }
  });

/**
 * いいね作成時のトリガー関数
 * countdownLikesコレクションにドキュメントが作成されたときに、
 * 対応するカウントダウンのlikesCountを更新
 */
export const onLikeCreate = functions.firestore
  .document("countdownLikes/{likeId}")
  .onCreate(async (snapshot, context) => {
    try {
      const likeData = snapshot.data();
      const countdownId = likeData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in like data");
        return;
      }

      // カウントダウンのlikesCountを+1
      await db.collection("counts").doc(countdownId).update({
        likesCount: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Updated likesCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error updating likes count:", error);
    }
  });

/**
 * いいね削除時のトリガー関数
 * countdownLikesコレクションからドキュメントが削除されたときに、
 * 対応するカウントダウンのlikesCountを更新
 */
export const onLikeDelete = functions.firestore
  .document("countdownLikes/{likeId}")
  .onDelete(async (snapshot, context) => {
    try {
      const likeData = snapshot.data();
      const countdownId = likeData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in like data");
        return;
      }

      // カウントダウンのlikesCountを-1
      await db.collection("counts").doc(countdownId).update({
        likesCount: admin.firestore.FieldValue.increment(-1),
      });

      console.log(`Decremented likesCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error decrementing likes count:", error);
    }
  });

/**
 * 閲覧数トラッキングのトリガー関数
 * viewsコレクションにドキュメントが作成されたときに、
 * 対応するカウントダウンのviewsCountを更新
 */
export const onViewCreate = functions.firestore
  .document("views/{viewId}")
  .onCreate(async (snapshot, context) => {
    try {
      const viewData = snapshot.data();
      const countdownId = viewData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in view data");
        return;
      }

      // カウントダウンのviewsCountを+1
      await db.collection("counts").doc(countdownId).update({
        viewsCount: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Updated viewsCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error updating views count:", error);
    }
  });

/**
 * 最近の閲覧数トラッキングのトリガー関数
 * recentViewsコレクションにドキュメントが作成されたときに、
 * 対応するカウントダウンのrecentViewsCountを更新
 */
export const onRecentViewCreate = functions.firestore
  .document("recentViews/{viewId}")
  .onCreate(async (snapshot, context) => {
    try {
      const viewData = snapshot.data();
      const countdownId = viewData.countdownId;

      if (!countdownId) {
        console.error("countdownId is missing in recent view data");
        return;
      }

      // カウントダウンのrecentViewsCountを+1
      await db.collection("counts").doc(countdownId).update({
        recentViewsCount: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Updated recentViewsCount for countdown: ${countdownId}`);
    } catch (error) {
      console.error("Error updating recent views count:", error);
    }
  });

/**
 * 定期的なトレンドランキング更新関数
 * Cloud Schedulerから5分ごとに実行される
 */
export const updateTrendRankings = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    try {
      console.log("Starting trend rankings update...");

      // 全カテゴリのランキングを更新
      const categories = ["overall", "ゲーム", "音楽", "アニメ", "ライブ", "推し活"];

      for (const category of categories) {
        await updateRankingForCategory(category);
      }

      console.log("Trend rankings update completed");
    } catch (error) {
      console.error("Error updating trend rankings:", error);
    }
  });

/**
 * 指定されたカテゴリのランキングを更新
 */
async function updateRankingForCategory(category: string) {
  try {
    // カウントダウンを取得
    let query = db.collection("counts") as admin.firestore.Query;

    if (category !== "overall") {
      query = query.where("category", "==", category);
    }

    const snapshot = await query.get();
    const countdowns: any[] = [];

    snapshot.forEach((doc) => {
      const data = doc.data();
      countdowns.push({
        id: doc.id,
        ...data,
        eventDate: data.eventDate.toDate(),
      });
    });

    // トレンドスコアを計算
    const rankings = countdowns.map((countdown) => {
      const trendScore = calculateTrendScore(
        countdown.participantsCount || 0,
        countdown.commentsCount || 0,
        countdown.likesCount || 0,
        0, // sharesCount - 今後実装
        countdown.eventDate
      );

      return {
        countdownId: countdown.id,
        eventName: countdown.eventName,
        category: category === "overall" ? "overall" : countdown.category,
        eventDate: countdown.eventDate,
        participantsCount: countdown.participantsCount || 0,
        commentsCount: countdown.commentsCount || 0,
        likesCount: countdown.likesCount || 0,
        sharesCount: 0,
        trendScore,
      };
    });

    // トレンドスコアでソート
    rankings.sort((a, b) => b.trendScore - a.trendScore);

    // 既存のランキングデータを削除
    const existingQuery = db.collection("trendRankings")
      .where("category", "==", category);
    const existingSnapshot = await existingQuery.get();

    const batch = db.batch();

    // 既存データを削除
    existingSnapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    // 新しいランキングデータを追加（上位50位まで）
    rankings.slice(0, 50).forEach((ranking, index) => {
      const docRef = db.collection("trendRankings").doc();
      batch.set(docRef, {
        ...ranking,
        rank: index + 1,
        eventDate: admin.firestore.Timestamp.fromDate(ranking.eventDate),
        updatedAt: admin.firestore.Timestamp.now(),
      });
    });

    await batch.commit();
    console.log(`Updated ranking for category: ${category}`);

  } catch (error) {
    console.error(`Error updating ranking for category ${category}:`, error);
  }
}

/**
 * トレンドスコア計算関数
 */
function calculateTrendScore(
  participantsCount: number,
  commentsCount: number,
  likesCount: number,
  sharesCount: number,
  eventDate: Date
): number {
  // 基本スコア: 参加者数 × 1.0 + コメント数 × 2.0 + いいね数 × 1.5 + シェア数 × 3.0
  const baseScore = participantsCount * 1.0 + 
                   commentsCount * 2.0 + 
                   likesCount * 1.5 + 
                   sharesCount * 3.0;

  // 時間による重み付け
  const now = new Date();
  const daysUntilEvent = Math.ceil((eventDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));

  let timeWeight = 1.0;
  if (daysUntilEvent <= 1) {
    timeWeight = 3.0; // 開催直前は3倍
  } else if (daysUntilEvent <= 3) {
    timeWeight = 2.0; // 3日前までは2倍
  } else if (daysUntilEvent <= 7) {
    timeWeight = 1.5; // 1週間前までは1.5倍
  }

  // 過去のイベントは重みを下げる
  if (daysUntilEvent < 0) {
    timeWeight = 0.1;
  }

  return baseScore * timeWeight;
}

/**
 * 手動でトレンドランキングを更新するHTTP関数（デバッグ用）
 */
export const manualUpdateTrendRankings = functions.https.onRequest(async (req, res) => {
  try {
    console.log("Manual trend rankings update started...");

    const categories = ["overall", "ゲーム", "音楽", "アニメ", "ライブ", "推し活"];

    for (const category of categories) {
      await updateRankingForCategory(category);
    }

    res.status(200).json({
      success: true,
      message: "Trend rankings updated successfully",
    });
  } catch (error) {
    console.error("Error in manual update:", error);
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred",
    });
  }
});

/**
 * 分散カウンターの実装（高負荷対応）
 */
export const incrementDistributedCounter = functions.https.onCall(async (data, context) => {
  const { countdownId, field, increment = 1 } = data;

  if (!countdownId || !field) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "countdownId and field are required"
    );
  }

  try {
    // 分散カウンターの実装
    const numShards = 10; // シャード数
    const shardId = Math.floor(Math.random() * numShards);
    
    // シャードドキュメントを更新
    await db.collection("countdownShards")
      .doc(`${countdownId}_${field}_${shardId}`)
      .set({
        count: admin.firestore.FieldValue.increment(increment),
      }, { merge: true });

    // メインドキュメントも更新（リアルタイム表示用）
    await db.collection("counts").doc(countdownId).update({
      [field]: admin.firestore.FieldValue.increment(increment),
    });

    return { success: true };
  } catch (error) {
    console.error("Error incrementing distributed counter:", error);
    throw new functions.https.HttpsError("internal", "Failed to increment counter");
  }
});

/**
 * 分散カウンターの合計値を取得
 */
export const getDistributedCounterTotal = functions.https.onCall(async (data, context) => {
  const { countdownId, field } = data;

  if (!countdownId || !field) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "countdownId and field are required"
    );
  }

  try {
    const shardsSnapshot = await db.collection("countdownShards")
      .where(admin.firestore.FieldPath.documentId(), ">=", `${countdownId}_${field}_`)
      .where(admin.firestore.FieldPath.documentId(), "<", `${countdownId}_${field}_~`)
      .get();

    let total = 0;
    shardsSnapshot.forEach((doc) => {
      total += doc.data().count || 0;
    });

    return { total };
  } catch (error) {
    console.error("Error getting distributed counter total:", error);
    throw new functions.https.HttpsError("internal", "Failed to get counter total");
  }
});