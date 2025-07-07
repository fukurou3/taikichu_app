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

  /// 【非推奨】直接コメント作成
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use createCommentEvent() instead')
  static Future<void> addComment(Comment comment) async {
    throw UnimplementedError('Direct comment creation disabled for security - use unified pipeline');
  }

  /// 【統一パイプライン】コメント作成イベント送信
  static Future<bool> createCommentEvent(Comment comment) async {
    try {
      return await UnifiedAnalyticsService.sendEvent(
        type: 'comment_created',
        countdownId: comment.countdownId,
        metadata: {
          'authorId': comment.authorId,
          'content': comment.content,
          'commentId': comment.id,
        },
      );
    } catch (e) {
      print('CommentService - Error creating comment event: $e');
      return false;
    }
  }

  /// 【非推奨】直接コメント削除
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use deleteCommentEvent() instead')
  static Future<void> deleteComment(String commentId) async {
    throw UnimplementedError('Direct comment deletion disabled for security - use unified pipeline');
  }

  /// 【統一パイプライン】コメント削除イベント送信
  static Future<bool> deleteCommentEvent(String commentId, String countdownId) async {
    try {
      return await UnifiedAnalyticsService.sendEvent(
        type: 'comment_deleted',
        countdownId: countdownId,
        metadata: {
          'commentId': commentId,
          'reason': 'user_request',
        },
      );
    } catch (e) {
      print('CommentService - Error deleting comment event: $e');
      return false;
    }
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