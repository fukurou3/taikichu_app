import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';

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
    await _firestore.collection(_collection).add(comment.toFirestore());
  }

  static Future<void> deleteComment(String commentId) async {
    await _firestore.collection(_collection).doc(commentId).delete();
  }

  static Future<int> getCommentCount(String countdownId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('countdownId', isEqualTo: countdownId)
        .get();
    return snapshot.docs.length;
  }
}