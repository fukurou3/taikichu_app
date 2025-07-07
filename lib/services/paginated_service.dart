import 'mvp_analytics_client.dart';

class PaginatedResult<T> {
  final List<T> items;
  final int nextOffset;
  final bool hasMore;

  PaginatedResult({
    required this.items,
    required this.nextOffset,
    required this.hasMore,
  });
}

class PaginatedService {
  static const int defaultPageSize = 10;

  /// 【移行完了】カウントダウンをページネーションで取得（バックエンドAPI経由）
  static Future<PaginatedResult<Map<String, dynamic>>> getCountdownsPaginated({
    int offset = 0,
    int limit = defaultPageSize,
    String? category,
  }) async {
    try {
      // バックエンドAPIからデータを取得（追加の1件でhasMoreを判定）
      final countdownsData = await MVPAnalyticsClient.getCountdowns(
        category: category,
        limit: limit + 1,
        offset: offset,
      );

      // 次のページがあるかチェック
      final hasMore = countdownsData.length > limit;
      final items = hasMore ? countdownsData.take(limit).toList() : countdownsData;

      return PaginatedResult<Map<String, dynamic>>(
        items: items,
        nextOffset: offset + items.length,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated countdowns: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        nextOffset: offset,
        hasMore: false,
      );
    }
  }

  /// 【移行完了】コメントをページネーションで取得（バックエンドAPI経由）
  static Future<PaginatedResult<Map<String, dynamic>>> getCommentsPaginated({
    required String countdownId,
    int offset = 0,
    int limit = defaultPageSize,
  }) async {
    try {
      // バックエンドAPIからコメントを取得
      final commentsData = await MVPAnalyticsClient.getComments(
        countdownId,
        limit: limit + 1,
        offset: offset,
      );

      final hasMore = commentsData.length > limit;
      final items = hasMore ? commentsData.take(limit).toList() : commentsData;

      return PaginatedResult<Map<String, dynamic>>(
        items: items,
        nextOffset: offset + items.length,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated comments: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        nextOffset: offset,
        hasMore: false,
      );
    }
  }

  /// 【移行完了】トレンドランキングをページネーションで取得（バックエンドAPI経由）
  static Future<PaginatedResult<Map<String, dynamic>>> getTrendRankingsPaginated({
    int offset = 0,
    int limit = defaultPageSize,
    String? category,
  }) async {
    try {
      // MVPAnalyticsClient のランキングAPIを使用
      final rankingItems = await MVPAnalyticsClient.getTrendRanking(
        category: category,
        limit: limit + 1,
      );

      final hasMore = rankingItems.length > limit;
      final items = hasMore ? rankingItems.take(limit).toList() : rankingItems;

      // TrendRankingItem を Map に変換
      final itemsAsMap = items.map((item) => item.toJson()).toList();

      return PaginatedResult<Map<String, dynamic>>(
        items: itemsAsMap,
        nextOffset: offset + items.length,
        hasMore: hasMore,
      );
    } catch (e) {
      print('Error getting paginated trend rankings: $e');
      return PaginatedResult<Map<String, dynamic>>(
        items: [],
        nextOffset: offset,
        hasMore: false,
      );
    }
  }
}