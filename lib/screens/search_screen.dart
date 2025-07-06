import 'package:flutter/material.dart';
import '../services/trend_ranking_service.dart';
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
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'トレンド',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        FutureBuilder<List<TrendRanking>>(
          future: TrendRankingService.getTrendRankings(
            type: RankingType.overall,
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
                        child: Text('${ranking.rank}'),
                      ),
                      title: Text(ranking.eventName),
                      subtitle: Text('カテゴリ: ${ranking.category} | スコア: ${ranking.trendScore.toInt()}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.grey[600]),
                          Text(' ${ranking.participantsCount}'),
                          const SizedBox(width: 8),
                          Icon(Icons.comment, size: 16, color: Colors.grey[600]),
                          Text(' ${ranking.commentsCount}'),
                          const SizedBox(width: 8),
                          Icon(Icons.favorite, size: 16, color: Colors.grey[600]),
                          Text(' ${ranking.participantsCount}'),
                        ],
                      ),
                      onTap: () {
                        final countdown = Countdown(
                          id: ranking.countdownId,
                          eventName: ranking.eventName,
                          eventDate: ranking.eventDate,
                          category: ranking.category,
                          creatorId: '',
                          participantsCount: ranking.participantsCount,
                          commentsCount: ranking.commentsCount,
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