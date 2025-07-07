import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'comments';

  static Stream<List<Comment>> getCommentsStream(String countdownId) {
    return _firestore
        .collection(_collection)
        .where('countdownId', isEqualTo: countdownId)
        .snapshots()
        .map((snapshot) {
      final comments = snapshot.docs.map((doc) {
        return Comment.fromFirestore(doc, null);
      }).toList();
      
      // アプリ側でソート
      comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return comments;
    });
  }

  static Future<void> addComment(Comment comment) async {
    // コメントをFirestoreに保存
    await _firestore.collection(_collection).add(comment.toFirestore());
    
    // 🚀 統一パイプライン: コメント追加イベント送信
    await UnifiedAnalyticsService.sendCommentEvent(comment.countdownId);
  }

  static Future<void> deleteComment(String commentId) async {
    await _firestore.collection(_collection).doc(commentId).delete();
  }

  static Future<int> getCommentCount(String countdownId) async {
    try {
      // 🚀 統一パイプライン: 1-5ms超高速レスポンス
      return await MVPAnalyticsClient.getCounterValue(
        countdownId: countdownId,
        counterType: 'comments',
      );
    } catch (e) {
      print('CommentService - Error getting comment count: $e');
      return 0;
    }
  }
}