import 'package:flutter/material.dart';
import '../services/optimized_stream_service.dart';
import '../services/trend_ranking_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import '../widgets/trend_ranking_card.dart';
import '../models/countdown.dart';
import '../models/trend_ranking.dart';
import 'thread_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'おすすめ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        StreamBuilder<List<Countdown>>(
          stream: OptimizedStreamService.getBatchedCountdownsStream(
            limit: 20,
            batchInterval: const Duration(seconds: 3),
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SliverToBoxAdapter(
                child: Center(child: Text('エラーが発生しました: ${snapshot.error}')),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final countdowns = snapshot.data ?? [];
            
            if (countdowns.isEmpty) {
              return const SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    'まだカウントダウンがありません。\n検索画面からカウントダウンを探しましょう！',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final countdown = countdowns[index];
                  
                  return EnhancedCountdownCard(countdown: countdown);
                },
                childCount: countdowns.length,
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}