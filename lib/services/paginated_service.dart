import 'package:cloud_firestore/cloud_firestore.dart';

class PaginatedResult<T> {
  final List<T> items;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;

  PaginatedResult({
    required this.items,
    this.lastDocument,
    required this.hasMore,
  });
}

class PaginatedService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int defaultPageSize = 10;

  /// カウントダウンをページネーションで取得
  static Future<PaginatedResult<Map<String, dynamic>>> getCountdownsPaginated({
    DocumentSnapshot? startAfter,
    int limit = defaultPageSize,
    String? category,
    String orderBy = 'eventDate',
    bool descending = false,
  }) async {
    try {
      Query query = _firestore.collection('counts');

      // カテゴリフィルター
      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      // ソート
      query = query.orderBy(orderBy, descending: descending);

      // ページネーション
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      // 制限 + 1（次のページがあるかチェック用）
      query = query.limit(limit + 1);

      final snapshot = await query.get();
      final docs = snapshot.docs;

      // 次のページがあるかチェック
      final hasMore = docs.length > limit;
      final items = hasMore ? docs.take(limit).toList() : docs;

      return PaginatedResult<Map<String, dynamic>>(
        items: items.map((doc) => {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }).toList(),
        lastDocument: items.isNotEmpty ? items.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated countdowns: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        hasMore: false,
      );
    }
  }

  /// コメントをページネーションで取得
  static Future<PaginatedResult<Map<String, dynamic>>> getCommentsPaginated({
    required String countdownId,
    DocumentSnapshot? startAfter,
    int limit = defaultPageSize,
  }) async {
    try {
      Query query = _firestore.collection('comments')
          .where('countdownId', isEqualTo: countdownId)
          .orderBy('createdAt', descending: false);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(limit + 1);

      final snapshot = await query.get();
      final docs = snapshot.docs;

      final hasMore = docs.length > limit;
      final items = hasMore ? docs.take(limit).toList() : docs;

      return PaginatedResult<Map<String, dynamic>>(
        items: items.map((doc) => {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }).toList(),
        lastDocument: items.isNotEmpty ? items.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated comments: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        hasMore: false,
      );
    }
  }

  /// トレンドランキングをページネーションで取得
  static Future<PaginatedResult<Map<String, dynamic>>> getTrendRankingsPaginated({
    DocumentSnapshot? startAfter,
    int limit = defaultPageSize,
    String category = 'overall',
  }) async {
    try {
      Query query = _firestore.collection('trendRankings')
          .where('category', isEqualTo: category)
          .orderBy('rank', descending: false);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(limit + 1);

      final snapshot = await query.get();
      final docs = snapshot.docs;

      final hasMore = docs.length > limit;
      final items = hasMore ? docs.take(limit).toList() : docs;

      return PaginatedResult<Map<String, dynamic>>(
        items: items.map((doc) => {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }).toList(),
        lastDocument: items.isNotEmpty ? items.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated trend rankings: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        hasMore: false,
      );
    }
  }

  /// 無限スクロール用のストリーム（リアルタイム更新対応）
  static Stream<List<Map<String, dynamic>>> getCountdownsStream({
    String? category,
    int limit = 20,
  }) {
    Query query = _firestore.collection('counts');

    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    return query
        .orderBy('eventDate', descending: false)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      }).toList();
    });
  }
}