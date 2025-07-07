import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';

class CountdownSearchService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// イベント名で類似のカウントダウンを検索
  static Future<List<Countdown>> searchSimilarCountdowns({
    required String eventName,
    String? category,
    DateTime? eventDate,
  }) async {
    try {
      List<Countdown> results = [];

      // 1. 完全一致検索
      final exactMatches = await _searchExactMatch(eventName, category);
      results.addAll(exactMatches);

      // 2. 部分一致検索（キーワードベース）
      final partialMatches = await _searchPartialMatch(eventName, category);
      results.addAll(partialMatches);

      // 3. 同日開催イベント検索
      if (eventDate != null) {
        final sameDayEvents = await _searchSameDayEvents(eventDate, category);
        results.addAll(sameDayEvents);
      }

      // 重複を除去し、関連度でソート
      final uniqueResults = _removeDuplicatesAndSort(results, eventName);
      
      return uniqueResults.take(10).toList(); // 最大10件
    } catch (e) {
      print('Error searching similar countdowns: $e');
      return [];
    }
  }

  /// Firestoreデータから Countdown オブジェクトを作成
  static Countdown _createCountdownFromData(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Countdown(
      id: doc.id,
      eventName: data['eventName'] as String,
      description: data['description'] as String?,
      eventDate: (data['eventDate'] as Timestamp).toDate(),
      category: data['category'] as String,
      imageUrl: data['imageUrl'] as String?,
      creatorId: data['creatorId'] as String,
      participantsCount: data['participantsCount'] as int? ?? 0,
      likesCount: data['likesCount'] as int? ?? 0,
      commentsCount: data['commentsCount'] as int? ?? 0,
      viewsCount: data['viewsCount'] as int? ?? 0,
      recentCommentsCount: data['recentCommentsCount'] as int? ?? 0,
      recentLikesCount: data['recentLikesCount'] as int? ?? 0,
      recentViewsCount: data['recentViewsCount'] as int? ?? 0,
      commentCount: data['commentCount'] as int? ?? data['commentsCount'] as int? ?? 0,
    );
  }

  /// 完全一致検索
  static Future<List<Countdown>> _searchExactMatch(String eventName, String? category) async {
    Query query = _firestore.collection('counts')
        .where('eventName', isEqualTo: eventName);

    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => _createCountdownFromData(doc)).toList();
  }

  /// 部分一致検索（キーワードベース）
  static Future<List<Countdown>> _searchPartialMatch(String eventName, String? category) async {
    // イベント名をキーワードに分割
    final keywords = _extractKeywords(eventName);
    if (keywords.isEmpty) return [];

    Query query = _firestore.collection('counts');
    
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    final snapshot = await query.get();
    final allCountdowns = snapshot.docs.map((doc) => _createCountdownFromData(doc)).toList();

    // キーワードマッチングでフィルタリング
    return allCountdowns.where((countdown) {
      final countdownKeywords = _extractKeywords(countdown.eventName);
      return _calculateKeywordSimilarity(keywords, countdownKeywords) > 0.3; // 30%以上の類似度
    }).toList();
  }

  /// 同日開催イベント検索
  static Future<List<Countdown>> _searchSameDayEvents(DateTime eventDate, String? category) async {
    final startOfDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    Query query = _firestore.collection('counts')
        .where('eventDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('eventDate', isLessThan: Timestamp.fromDate(endOfDay));

    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => _createCountdownFromData(doc)).toList();
  }

  /// キーワード抽出
  static List<String> _extractKeywords(String text) {
    // 日本語対応の簡易キーワード抽出
    final cleanText = text
        .replaceAll(RegExp(r'[【】()（）\\[\\]「」『』〈〉《》]'), ' ') // 括弧類を除去
        .replaceAll(RegExp(r'[!！?？。、，・\\s]+'), ' ') // 記号・空白を正規化
        .trim();

    final words = cleanText.split(' ')
        .where((word) => word.length >= 2) // 2文字以上
        .map((word) => word.toLowerCase())
        .toList();

    return words;
  }

  /// キーワード類似度計算
  static double _calculateKeywordSimilarity(List<String> keywords1, List<String> keywords2) {
    if (keywords1.isEmpty || keywords2.isEmpty) return 0.0;

    int matchCount = 0;
    for (final keyword1 in keywords1) {
      for (final keyword2 in keywords2) {
        if (keyword1 == keyword2 || 
            keyword1.contains(keyword2) || 
            keyword2.contains(keyword1)) {
          matchCount++;
          break;
        }
      }
    }

    return matchCount / keywords1.length;
  }

  /// 重複除去と関連度ソート
  static List<Countdown> _removeDuplicatesAndSort(List<Countdown> countdowns, String originalEventName) {
    final uniqueCountdowns = <String, Countdown>{};
    
    for (final countdown in countdowns) {
      if (!uniqueCountdowns.containsKey(countdown.id)) {
        uniqueCountdowns[countdown.id] = countdown;
      }
    }

    final result = uniqueCountdowns.values.toList();
    
    // 関連度でソート（完全一致 > 部分一致 > 同日開催の順）
    result.sort((a, b) {
      final aExact = a.eventName == originalEventName ? 3 : 0;
      final bExact = b.eventName == originalEventName ? 3 : 0;
      
      final aKeywords = _extractKeywords(originalEventName);
      final bAKeywords = _extractKeywords(a.eventName);
      final bBKeywords = _extractKeywords(b.eventName);
      
      final aSimilarity = _calculateKeywordSimilarity(aKeywords, bAKeywords);
      final bSimilarity = _calculateKeywordSimilarity(aKeywords, bBKeywords);
      
      final aScore = aExact + aSimilarity;
      final bScore = bExact + bSimilarity;
      
      return bScore.compareTo(aScore);
    });

    return result;
  }

  /// フリーテキスト検索
  static Future<List<Countdown>> searchCountdowns({
    required String searchText,
    String? category,
    int limit = 20,
  }) async {
    try {
      if (searchText.trim().isEmpty) {
        return await _getAllCountdowns(category: category, limit: limit);
      }

      return await searchSimilarCountdowns(
        eventName: searchText,
        category: category,
      );
    } catch (e) {
      print('Error in searchCountdowns: $e');
      return [];
    }
  }

  /// 全カウントダウン取得（検索文字列が空の場合）
  static Future<List<Countdown>> _getAllCountdowns({
    String? category,
    int limit = 20,
  }) async {
    Query query = _firestore.collection('counts');
    
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    query = query.orderBy('eventDate', descending: false).limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => _createCountdownFromData(doc)).toList();
  }

  /// 類似度判定（重複チェック用）
  static bool isSimilarCountdown({
    required String newEventName,
    required DateTime newEventDate,
    required String newCategory,
    required Countdown existingCountdown,
  }) {
    // 同じカテゴリかチェック
    if (newCategory != existingCountdown.category) return false;

    // 同日または近い日付かチェック
    final daysDifference = newEventDate.difference(existingCountdown.eventDate).inDays.abs();
    if (daysDifference > 7) return false; // 1週間以上離れていれば別イベント

    // イベント名の類似度チェック
    final newKeywords = _extractKeywords(newEventName);
    final existingKeywords = _extractKeywords(existingCountdown.eventName);
    final similarity = _calculateKeywordSimilarity(newKeywords, existingKeywords);

    return similarity > 0.7; // 70%以上の類似度で重複判定
  }

  /// 人気のカテゴリを取得
  static Future<List<String>> getPopularCategories() async {
    try {
      final snapshot = await _firestore.collection('counts').get();
      final categoryCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final category = data['category'] as String? ?? 'その他';
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }

      final sortedCategories = categoryCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedCategories.map((entry) => entry.key).take(5).toList();
    } catch (e) {
      print('Error getting popular categories: $e');
      return ['ゲーム', '音楽', 'アニメ', 'ライブ', '推し活'];
    }
  }
}