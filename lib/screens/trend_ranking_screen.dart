import 'package:flutter/material.dart';
import '../models/trend_ranking.dart';
import '../services/mvp_analytics_client.dart';
import '../widgets/trend_ranking_card.dart';

class TrendRankingScreen extends StatefulWidget {
  const TrendRankingScreen({super.key});

  @override
  State<TrendRankingScreen> createState() => _TrendRankingScreenState();
}

class _TrendRankingScreenState extends State<TrendRankingScreen> {
  RankingType _selectedType = RankingType.overall;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('トレンドランキング'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // カテゴリタブ
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: RankingType.values.map((type) {
                final isSelected = _selectedType == type;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedType = type;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.red : Colors.grey[300]!,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        type.displayName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // ランキング一覧
          Expanded(
            child: FutureBuilder<List<TrendRankingItem>>(
              future: MVPAnalyticsClient.getTrendRanking(
                category: _selectedType == RankingType.overall ? null : _selectedType.displayName,
                limit: 20,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('エラーが発生しました: ${snapshot.error}'),
                  );
                }

                final rankings = snapshot.data ?? [];

                if (rankings.isEmpty) {
                  return const Center(
                    child: Text(
                      'ランキングデータがありません',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rankings.length,
                    itemBuilder: (context, index) {
                      final ranking = rankings[index];
                      final trendRanking = TrendRanking(
                        countdownId: ranking.countdownId,
                        eventName: ranking.countdownId,
                        category: _selectedType.displayName,
                        eventDate: DateTime.now().add(const Duration(days: 1)),
                        participantsCount: 0,
                        commentsCount: 0,
                        sharesCount: 0,
                        trendScore: ranking.trendScore,
                        rank: index + 1,
                        updatedAt: DateTime.now(),
                      );
                      return TrendRankingCard(ranking: trendRanking);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}