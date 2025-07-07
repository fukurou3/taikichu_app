import 'package:flutter/material.dart';
import '../services/optimized_stream_service.dart';
import '../services/scalable_participant_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import '../models/countdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _participatedIds = [];
  bool _isLoadingParticipants = true;
  bool _showParticipatedOnly = false; // 参加済みのみ表示するかのフラグ

  @override
  void initState() {
    super.initState();
    _loadParticipatedIds();
  }

  Future<void> _loadParticipatedIds() async {
    try {
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final ids = await ScalableParticipantService.getUserParticipatedCountdowns()
          .timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          _participatedIds = ids;
          _isLoadingParticipants = false;
          // 参加しているカウントダウンがある場合のみ、参加済みを表示
          _showParticipatedOnly = ids.isNotEmpty;
        });
      }
    } catch (e) {
      // エラー時は全カウントダウンを表示
      if (mounted) {
        setState(() {
          _participatedIds = [];
          _isLoadingParticipants = false;
          _showParticipatedOnly = false;
        });
      }
    }
  }

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
                    _showParticipatedOnly ? '参加中のカウントダウン' : 'おすすめ',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (!_isLoadingParticipants && _participatedIds.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showParticipatedOnly = !_showParticipatedOnly;
                        });
                      },
                      child: Text(
                        _showParticipatedOnly ? 'すべて表示' : '参加中のみ',
                        style: const TextStyle(
                          color: Color(0xFF1DA1F2),
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _isLoadingParticipants
              ? const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              : StreamBuilder<List<Countdown>>(
                  stream: OptimizedStreamService.getBatchedCountdownsStream(
                    limit: 50,
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

                    final allCountdowns = snapshot.data ?? [];
                    
                    // 表示するカウントダウンを決定
                    final countdowns = _showParticipatedOnly
                        ? (allCountdowns
                            .where((countdown) => _participatedIds.contains(countdown.id))
                            .toList()
                          ..sort((a, b) {
                            final now = DateTime.now();
                            final diffA = a.eventDate.difference(now);
                            final diffB = b.eventDate.difference(now);
                            
                            // 終了したイベントは後ろに
                            if (diffA.isNegative && !diffB.isNegative) return 1;
                            if (!diffA.isNegative && diffB.isNegative) return -1;
                            
                            // 残り時間が短い順
                            return diffA.compareTo(diffB);
                          }))
                        : allCountdowns;
                    
                    if (countdowns.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _showParticipatedOnly
                                  ? '参加しているカウントダウンがありません。\n詳細画面で参加者アイコンをタップして参加しましょう！'
                                  : 'まだカウントダウンがありません。',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
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