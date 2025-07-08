// Simplified Cloud Functions for Phase0 v2.1
// Minimal functions for daily aggregation and cost monitoring

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Import billing monitor functions
export {
  monitorDailyBudget,
  monitorFirestoreUsage,
  budgetHealthCheck
} from './billing-monitor';

admin.initializeApp();
const db = admin.firestore();

// 日次集計関数（毎日2時に実行）
export const dailyAggregation = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('Asia/Tokyo')
  .onRun(async (context) => {
    const today = new Date().toISOString().split('T')[0];
    
    try {
      // DAU計算
      const dauSnapshot = await db
        .collection('aggregations')
        .doc('dau')
        .collection('daily')
        .doc(today)
        .get();
      
      const dauCount = dauSnapshot.exists 
        ? Object.keys(dauSnapshot.data() || {}).length 
        : 0;
      
      // 新規ユーザー数計算
      const registrationsSnapshot = await db
        .collection('aggregations')
        .doc('registrations')
        .collection('daily')
        .doc(today)
        .get();
      
      const newUsersCount = registrationsSnapshot.exists
        ? Object.keys(registrationsSnapshot.data() || {}).length
        : 0;
      
      // 投稿数計算
      const postsSnapshot = await db
        .collection('posts')
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(new Date(today)))
        .where('createdAt', '<', admin.firestore.Timestamp.fromDate(new Date(new Date(today).getTime() + 24 * 60 * 60 * 1000)))
        .get();
      
      const postsCount = postsSnapshot.size;
      
      // 結果をFirestoreに保存
      await db.collection('daily_stats').doc(today).set({
        date: today,
        dau: dauCount,
        newUsers: newUsersCount,
        postsCreated: postsCount,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      console.log(`Daily aggregation completed for ${today}: DAU=${dauCount}, NewUsers=${newUsersCount}, Posts=${postsCount}`);
      
    } catch (error) {
      console.error('Error in daily aggregation:', error);
    }
  });

// Firestore読み取り監視（コスト管理用）
export const monitorFirestoreReads = functions.pubsub
  .schedule('0 */4 * * *') // 4時間ごと
  .timeZone('Asia/Tokyo')
  .onRun(async (context) => {
    try {
      // 簡単な読み取りカウント（実際の実装ではCloud Monitoringのメトリクスを使用）
      const currentHour = new Date().getHours();
      const estimatedReads = currentHour * 1000000; // 仮の推定値
      
      const maxDailyReads = 40000000; // 40M reads per day limit
      const currentEstimate = estimatedReads * (24 / currentHour);
      
      if (currentEstimate > maxDailyReads * 0.8) {
        console.warn(`High Firestore read usage detected: ${currentEstimate} (80% of limit)`);
        
        // アラート用のドキュメント作成
        await db.collection('alerts').add({
          type: 'high_firestore_usage',
          estimatedDailyReads: currentEstimate,
          limit: maxDailyReads,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      
    } catch (error) {
      console.error('Error monitoring Firestore reads:', error);
    }
  });

// 不要なinboxアイテム削除（週次実行）
export const cleanupInboxItems = functions.pubsub
  .schedule('0 3 * * 0') // 毎週日曜日3時
  .timeZone('Asia/Tokyo')
  .onRun(async (context) => {
    try {
      const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      
      // 各ユーザーのInboxをクリーンアップ（サンプル実装）
      const usersSnapshot = await db.collection('users').limit(100).get();
      
      const batch = db.batch();
      let deleteCount = 0;
      
      for (const userDoc of usersSnapshot.docs) {
        const oldInboxItems = await db
          .collection('inbox')
          .doc(userDoc.id)
          .collection('posts')
          .where('createdAt', '<', admin.firestore.Timestamp.fromDate(oneWeekAgo))
          .orderBy('createdAt')
          .limit(50) // バッチ制限を考慮
          .get();
        
        oldInboxItems.docs.forEach(doc => {
          batch.delete(doc.ref);
          deleteCount++;
        });
        
        // バッチ制限に達したらコミット
        if (deleteCount >= 400) {
          await batch.commit();
          deleteCount = 0;
        }
      }
      
      if (deleteCount > 0) {
        await batch.commit();
      }
      
      console.log(`Cleaned up ${deleteCount} old inbox items`);
      
    } catch (error) {
      console.error('Error cleaning up inbox items:', error);
    }
  });

// ユーザーアクティビティ記録用のトリガー
export const recordUserActivity = functions.auth.user().onCreate(async (user) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    
    // ユーザー登録を記録
    await db
      .collection('aggregations')
      .doc('registrations')
      .collection('daily')
      .doc(today)
      .set({
        [user.uid]: {
          registeredAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      }, { merge: true });
    
    // ユーザードキュメント作成
    await db.collection('users').doc(user.uid).set({
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoURL: user.photoURL,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      followersCount: 0,
      followingCount: 0,
      postsCount: 0,
    });
    
    console.log(`New user registered: ${user.uid}`);
    
  } catch (error) {
    console.error('Error recording user activity:', error);
  }
});

// システム健康状態の確認用エンドポイント
export const healthCheck = functions.https.onRequest(async (req, res) => {
  try {
    res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: "phase0-v2.1",
      message: "Simplified Firestore-only architecture"
    });
  } catch (error) {
    res.status(500).json({
      status: "error",
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});