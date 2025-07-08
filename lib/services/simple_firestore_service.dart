// Simple Firestore Service for Phase0 v2.1
// Implements Write Fan-out strategy for timeline optimization

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import '../models/comment.dart';

class SimpleFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  // ========================================
  // タイムライン関連 (Write Fan-out方式)
  // ========================================
  
  /// ユーザーのタイムライン取得 (Inbox方式)
  static Future<List<Countdown>> getTimeline(String userId, {int limit = 100}) async {
    try {
      final snapshot = await _db
          .collection('inbox')
          .doc(userId)
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      if (snapshot.docs.isEmpty) {
        // Inboxが空の場合は、フォロー中のユーザーから動的生成
        return await _generateTimelineFromFollowing(userId, limit);
      }
      
      final List<Countdown> timeline = [];
      for (final doc in snapshot.docs) {
        final inboxData = doc.data();
        final postDoc = await _db.collection('posts').doc(inboxData['postId']).get();
        
        if (postDoc.exists) {
          timeline.add(Countdown.fromFirestore(postDoc));
        }
      }
      
      return timeline;
    } catch (e) {
      print('Error getting timeline: $e');
      return [];
    }
  }
  
  /// タイムラインストリーム取得
  static Stream<List<Countdown>> getTimelineStream(String userId, {int limit = 100}) {
    return _db
        .collection('inbox')
        .doc(userId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) {
        return await _generateTimelineFromFollowing(userId, limit);
      }
      
      final List<Countdown> timeline = [];
      for (final doc in snapshot.docs) {
        final inboxData = doc.data();
        final postDoc = await _db.collection('posts').doc(inboxData['postId']).get();
        
        if (postDoc.exists) {
          timeline.add(Countdown.fromFirestore(postDoc));
        }
      }
      
      return timeline;
    });
  }
  
  /// フォロー中のユーザーから動的タイムライン生成 (Fallback)
  static Future<List<Countdown>> _generateTimelineFromFollowing(String userId, int limit) async {
    try {
      // フォロー中のユーザー取得
      final followingSnapshot = await _db
          .collection('follows')
          .where('followerId', isEqualTo: userId)
          .get();
      
      if (followingSnapshot.docs.isEmpty) {
        return [];
      }
      
      final followingIds = followingSnapshot.docs
          .map((doc) => doc.data()['followingId'] as String)
          .toList();
      
      // フォロー中のユーザーの投稿を取得
      final postsSnapshot = await _db
          .collection('posts')
          .where('creatorId', whereIn: followingIds.take(10).toList()) // Firestore制限対応
          .where('status', isEqualTo: 'visible')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return postsSnapshot.docs
          .map((doc) => Countdown.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error generating timeline from following: $e');
      return [];
    }
  }
  
  // ========================================
  // 投稿関連
  // ========================================
  
  /// 投稿作成 (Write Fan-out実行)
  static Future<void> createPost(Countdown post) async {
    final batch = _db.batch();
    
    try {
      // 1. 投稿をpostsコレクションに保存
      final postRef = _db.collection('posts').doc(post.id);
      batch.set(postRef, post.toFirestore());
      
      // 2. バッチコミット
      await batch.commit();
      
      // 3. 非同期でFan-out実行
      await _executeFanout(post);
      
    } catch (e) {
      print('Error creating post: $e');
      rethrow;
    }
  }
  
  /// Fan-out実行 (フォロワーのInboxに配信)
  static Future<void> _executeFanout(Countdown post) async {
    try {
      // フォロワー取得
      final followersSnapshot = await _db
          .collection('follows')
          .where('followingId', isEqualTo: post.creatorId)
          .get();
      
      final batch = _db.batch();
      int batchCount = 0;
      
      for (final followerDoc in followersSnapshot.docs) {
        final followerId = followerDoc.data()['followerId'] as String;
        
        // 各フォロワーのInboxに追加
        final inboxRef = _db
            .collection('inbox')
            .doc(followerId)
            .collection('posts')
            .doc(post.id);
        
        batch.set(inboxRef, {
          'postId': post.id,
          'createdAt': post.createdAt,
          'creatorId': post.creatorId,
          'eventName': post.eventName,
          'category': post.category,
          'eventDate': post.eventDate,
        });
        
        batchCount++;
        
        // Firestoreのバッチ制限(500)に達したらコミット
        if (batchCount >= 450) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      // 残りのバッチをコミット
      if (batchCount > 0) {
        await batch.commit();
      }
      
    } catch (e) {
      print('Error executing fanout: $e');
    }
  }
  
  // ========================================
  // ユーザー関連
  // ========================================
  
  /// ユーザー情報取得
  static Future<Map<String, dynamic>?> getUser(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }
  
  /// ユーザー作成
  static Future<void> createUser(Map<String, dynamic> userData) async {
    try {
      await _db.collection('users').doc(userData['uid']).set({
        ...userData,
        'createdAt': FieldValue.serverTimestamp(),
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
      });
    } catch (e) {
      print('Error creating user: $e');
      rethrow;
    }
  }
  
  // ========================================
  // フォロー関連
  // ========================================
  
  /// フォロー状態確認
  static Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    try {
      final doc = await _db
          .collection('follows')
          .where('followerId', isEqualTo: currentUserId)
          .where('followingId', isEqualTo: targetUserId)
          .limit(1)
          .get();
      
      return doc.docs.isNotEmpty;
    } catch (e) {
      print('Error checking follow status: $e');
      return false;
    }
  }
  
  /// フォロー実行
  static Future<void> followUser(String targetUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    final batch = _db.batch();
    
    try {
      // フォロー関係作成
      final followRef = _db.collection('follows').doc();
      batch.set(followRef, {
        'followerId': currentUser.uid,
        'followingId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // フォロワー数更新
      final targetUserRef = _db.collection('users').doc(targetUserId);
      batch.update(targetUserRef, {'followersCount': FieldValue.increment(1)});
      
      // フォロー中数更新
      final currentUserRef = _db.collection('users').doc(currentUser.uid);
      batch.update(currentUserRef, {'followingCount': FieldValue.increment(1)});
      
      await batch.commit();
      
    } catch (e) {
      print('Error following user: $e');
      rethrow;
    }
  }
  
  /// アンフォロー実行
  static Future<void> unfollowUser(String targetUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    try {
      // フォロー関係取得
      final followSnapshot = await _db
          .collection('follows')
          .where('followerId', isEqualTo: currentUser.uid)
          .where('followingId', isEqualTo: targetUserId)
          .limit(1)
          .get();
      
      if (followSnapshot.docs.isEmpty) return;
      
      final batch = _db.batch();
      
      // フォロー関係削除
      batch.delete(followSnapshot.docs.first.reference);
      
      // フォロワー数更新
      final targetUserRef = _db.collection('users').doc(targetUserId);
      batch.update(targetUserRef, {'followersCount': FieldValue.increment(-1)});
      
      // フォロー中数更新
      final currentUserRef = _db.collection('users').doc(currentUser.uid);
      batch.update(currentUserRef, {'followingCount': FieldValue.increment(-1)});
      
      await batch.commit();
      
    } catch (e) {
      print('Error unfollowing user: $e');
      rethrow;
    }
  }
  
  /// フォロワー数取得
  static Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return {'followers': 0, 'following': 0};
      }
      
      final data = userDoc.data()!;
      return {
        'followers': data['followersCount'] ?? 0,
        'following': data['followingCount'] ?? 0,
      };
    } catch (e) {
      print('Error getting follow counts: $e');
      return {'followers': 0, 'following': 0};
    }
  }
  
  // ========================================
  // いいね関連
  // ========================================
  
  /// いいね実行
  static Future<void> likePost(String postId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    final batch = _db.batch();
    
    try {
      // いいね記録作成
      final likeRef = _db.collection('likes').doc('${currentUser.uid}_$postId');
      batch.set(likeRef, {
        'userId': currentUser.uid,
        'postId': postId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 投稿のいいね数更新
      final postRef = _db.collection('posts').doc(postId);
      batch.update(postRef, {'likesCount': FieldValue.increment(1)});
      
      await batch.commit();
      
    } catch (e) {
      print('Error liking post: $e');
      rethrow;
    }
  }
  
  /// いいね取消
  static Future<void> unlikePost(String postId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    final batch = _db.batch();
    
    try {
      // いいね記録削除
      final likeRef = _db.collection('likes').doc('${currentUser.uid}_$postId');
      batch.delete(likeRef);
      
      // 投稿のいいね数更新
      final postRef = _db.collection('posts').doc(postId);
      batch.update(postRef, {'likesCount': FieldValue.increment(-1)});
      
      await batch.commit();
      
    } catch (e) {
      print('Error unliking post: $e');
      rethrow;
    }
  }
  
  /// いいね状態確認
  static Future<bool> isLiked(String postId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    
    try {
      final doc = await _db.collection('likes').doc('${currentUser.uid}_$postId').get();
      return doc.exists;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }
  
  // ========================================
  // コメント関連
  // ========================================
  
  /// コメント取得
  static Future<List<Comment>> getComments(String postId, {int limit = 100}) async {
    try {
      final snapshot = await _db
          .collection('comments')
          .where('postId', isEqualTo: postId)
          .where('status', isEqualTo: 'visible')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => Comment.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting comments: $e');
      return [];
    }
  }
  
  /// コメント作成
  static Future<void> createComment(Comment comment) async {
    final batch = _db.batch();
    
    try {
      // コメント作成
      final commentRef = _db.collection('comments').doc(comment.id);
      batch.set(commentRef, comment.toFirestore());
      
      // 投稿のコメント数更新
      final postRef = _db.collection('posts').doc(comment.postId);
      batch.update(postRef, {'commentsCount': FieldValue.increment(1)});
      
      await batch.commit();
      
    } catch (e) {
      print('Error creating comment: $e');
      rethrow;
    }
  }
  
  // ========================================
  // 検索関連
  // ========================================
  
  /// 投稿検索
  static Future<List<Countdown>> searchPosts(String query, {int limit = 20}) async {
    try {
      // カテゴリで検索
      final categorySnapshot = await _db
          .collection('posts')
          .where('category', isEqualTo: query.toLowerCase())
          .where('status', isEqualTo: 'visible')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      final List<Countdown> results = categorySnapshot.docs
          .map((doc) => Countdown.fromFirestore(doc))
          .toList();
      
      // 結果が少ない場合は、イベント名での部分一致も試行
      if (results.length < limit / 2) {
        final nameSnapshot = await _db
            .collection('posts')
            .where('eventName', isGreaterThanOrEqualTo: query)
            .where('eventName', isLessThan: query + '\uf8ff')
            .where('status', isEqualTo: 'visible')
            .orderBy('eventName')
            .orderBy('createdAt', descending: true)
            .limit(limit - results.length)
            .get();
        
        results.addAll(nameSnapshot.docs
            .map((doc) => Countdown.fromFirestore(doc))
            .where((post) => !results.any((existing) => existing.id == post.id)));
      }
      
      return results;
    } catch (e) {
      print('Error searching posts: $e');
      return [];
    }
  }
  
  // ========================================
  // 集計関連
  // ========================================
  
  /// 日次アクティブユーザー記録
  static Future<void> recordDailyActiveUser(String userId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    try {
      await _db
          .collection('aggregations')
          .doc('dau')
          .collection('daily')
          .doc(today)
          .set({
        userId: true,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error recording DAU: $e');
    }
  }
  
  /// リテンション計算用のユーザー登録日記録
  static Future<void> recordUserRegistration(String userId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    try {
      await _db
          .collection('aggregations')
          .doc('registrations')
          .collection('daily')
          .doc(today)
          .set({
        userId: {
          'registeredAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error recording user registration: $e');
    }
  }
}