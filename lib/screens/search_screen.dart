import 'package:flutter/material.dart';
import '../services/mvp_analytics_client.dart';
import '../models/trend_ranking.dart';
import '../models/countdown.dart';
import 'thread_screen.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // 検索枠
              Container(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'トレンドを検索',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // トレンドタイトル
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Text(
                      'トレンド',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        FutureBuilder<List<TrendRankingItem>>(
          future: MVPAnalyticsClient.getTrendRanking(
            limit: 50,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Text('ランキングの読み込みエラー: ${snapshot.error}'),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final rankings = snapshot.data ?? [];
            
            if (rankings.isEmpty) {
              return const SliverToBoxAdapter(
                child: Center(child: Text('まだトレンドはありません。')),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ranking = rankings[index];
                  final rank = index + 1;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: index == 0 ? Colors.amber : 
                                        index == 1 ? Colors.grey[400] :
                                        Colors.brown[300],
                        child: Text('$rank'),
                      ),
                      title: Text(ranking.countdownId),
                      subtitle: Text('スコア: ${ranking.trendScore.toInt()}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up, size: 16, color: Colors.grey[600]),
                          Text(' ${ranking.trendScore.toInt()}'),
                        ],
                      ),
                      onTap: () {
                        final countdown = Countdown(
                          id: ranking.countdownId,
                          eventName: ranking.countdownId,
                          eventDate: DateTime.now().add(const Duration(days: 1)),
                          category: 'トレンド',
                          creatorId: '',
                          participantsCount: 0,
                          commentsCount: 0,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ThreadScreen(countdown: countdown),
                          ),
                        );
                      },
                    ),
                  );
                },
                childCount: rankings.length,
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}