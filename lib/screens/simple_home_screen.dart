import 'package:flutter/material.dart';
import '../services/simple_stream_service.dart';
import '../services/scalable_participant_service.dart';
import '../services/timeline_stream_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import '../models/countdown.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  bool _showParticipatedOnly = false;
  List<String> _participatedIds = [];
  bool _isLoadingParticipants = false;

  @override
  void initState() {
    super.initState();
    _loadParticipatedIds();
  }

  Future<void> _loadParticipatedIds() async {
    setState(() {
      _isLoadingParticipants = true;
    });

    try {
      print('SimpleHomeScreen - Loading participated IDs...');
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final ids = await ScalableParticipantService.getUserParticipatedCountdowns()
          .timeout(const Duration(seconds: 10));
      
      print('SimpleHomeScreen - Got participated IDs: $ids');
      
      if (mounted) {
        setState(() {
          _participatedIds = ids;
          _isLoadingParticipants = false;
        });
      }
    } catch (e) {
      print('SimpleHomeScreen - Error loading participated IDs: $e');
      if (mounted) {
        setState(() {
          _participatedIds = [];
          _isLoadingParticipants = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '待機中。',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
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
      body: Column(
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
                      'カウントダウンを検索',
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
          
          // 現在の表示モード
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _showParticipatedOnly ? '参加中のカウントダウン' : 'おすすめ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                if (_isLoadingParticipants)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // カウントダウンリスト
          Expanded(
            child: StreamBuilder<List<Countdown>>(
              stream: _showParticipatedOnly 
                ? TimelineStreamService.getPersonalTimelineStream(limit: 50)
                : TimelineStreamService.getGlobalTimelineStream(limit: 50),
              builder: (context, snapshot) {
                print('SimpleHomeScreen - StreamBuilder state: ${snapshot.connectionState}');
                print('SimpleHomeScreen - Has error: ${snapshot.hasError}');
                print('SimpleHomeScreen - Error: ${snapshot.error}');
                print('SimpleHomeScreen - Data length: ${snapshot.data?.length ?? 0}');
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('エラーが発生しました'),
                        const SizedBox(height: 8),
                        Text('${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {}); // 再構築をトリガー
                          },
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('カウントダウンを読み込み中...'),
                      ],
                    ),
                  );
                }

                final displayCountdowns = snapshot.data ?? [];
                print('SimpleHomeScreen - Display countdowns: ${displayCountdowns.length}');

                if (displayCountdowns.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _showParticipatedOnly
                              ? '参加しているカウントダウンがありません。\n詳細画面で参加者アイコンをタップして参加しましょう！'
                              : 'まだカウントダウンがありません。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: displayCountdowns.length,
                  itemBuilder: (context, index) {
                    final countdown = displayCountdowns[index];
                    return EnhancedCountdownCard(countdown: countdown);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}