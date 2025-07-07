import 'package:cloud_firestore/cloud_firestore.dart';

class RankingItem {
  final String countdownId;
  final String eventName;
  final String category;
  final double score;

  RankingItem({
    required this.countdownId,
    required this.eventName,
    required this.category,
    required this.score,
  });

  factory RankingItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return RankingItem(
      countdownId: data?['countdownId'] as String,
      eventName: data?['eventName'] as String,
      category: data?['category'] as String,
      score: (data?['trendScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'countdownId': countdownId,
      'eventName': eventName,
      'category': category,
      'trendScore': score,
    };
  }
}