import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';

class SimpleStreamService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// シンプルなカウントダウンストリーム（キャッシュなし、複雑性なし）
  static Stream<List<Countdown>> getCountdownsStream({
    String? category,
    int limit = 50,
  }) {
    print('SimpleStreamService - Starting stream with category: $category, limit: $limit');
    
    Query query = _firestore.collection('counts');
    
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    
    query = query.orderBy('eventDate', descending: false).limit(limit);
    
    return query.snapshots().map((snapshot) {
      print('SimpleStreamService - Received ${snapshot.docs.length} documents');
      
      final countdowns = snapshot.docs.map((doc) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final description = data['description'] as String?;
          
          print('SimpleStreamService - Doc ${doc.id}: eventName="${data['eventName']}", description="$description"');
          
          return Countdown(
            id: doc.id,
            eventName: data['eventName'] as String? ?? '無題',
            description: description,
            eventDate: (data['eventDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
            category: data['category'] as String? ?? 'その他',
            imageUrl: data['imageUrl'] as String?,
            creatorId: data['creatorId'] as String? ?? 'unknown',
            participantsCount: data['participantsCount'] as int? ?? 0,
            likesCount: data['likesCount'] as int? ?? 0,
            commentsCount: data['commentsCount'] as int? ?? 0,
            viewsCount: data['viewsCount'] as int? ?? 0,
            recentCommentsCount: data['recentCommentsCount'] as int? ?? 0,
            recentLikesCount: data['recentLikesCount'] as int? ?? 0,
            recentViewsCount: data['recentViewsCount'] as int? ?? 0,
          );
        } catch (e) {
          print('SimpleStreamService - Error creating countdown from doc ${doc.id}: $e');
          // エラーが発生した場合はスキップ
          return null;
        }
      }).where((countdown) => countdown != null).cast<Countdown>().toList();
      
      print('SimpleStreamService - Successfully created ${countdowns.length} countdown objects');
      return countdowns;
    }).handleError((error) {
      print('SimpleStreamService - Stream error: $error');
      return <Countdown>[];
    });
  }

  /// コメントストリーム（シンプル版）
  static Stream<List<Map<String, dynamic>>> getCommentsStream(String countdownId) {
    return _firestore
        .collection('comments')
        .where('countdownId', isEqualTo: countdownId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
              'id': doc.id,
              ...doc.data(),
            }).toList())
        .handleError((error) {
          print('SimpleStreamService - Comments error: $error');
          return <Map<String, dynamic>>[];
        });
  }
}