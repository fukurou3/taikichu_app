import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/simple_stream_service.dart';
import '../services/scalable_participant_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import '../models/countdown.dart';

class SimpleProfileScreen extends StatefulWidget {
  const SimpleProfileScreen({super.key});

  @override
  State<SimpleProfileScreen> createState() => _SimpleProfileScreenState();
}

class _SimpleProfileScreenState extends State<SimpleProfileScreen> {
  final TextEditingController _bioController = TextEditingController();
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
      print('SimpleProfileScreen - Loading participated IDs...');
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final ids = await ScalableParticipantService.getUserParticipatedCountdowns()
          .timeout(const Duration(seconds: 10));
      
      print('SimpleProfileScreen - Got participated IDs: $ids');
      
      if (mounted) {
        setState(() {
          _participatedIds = ids;
          _isLoadingParticipants = false;
        });
      }
    } catch (e) {
      print('SimpleProfileScreen - Error loading participated IDs: $e');
      if (mounted) {
        setState(() {
          _participatedIds = [];
          _isLoadingParticipants = false;
        });
      }
    }
  }
  
  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'プロフィール',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // プロフィール情報
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF1DA1F2).withOpacity(0.1),
                      child: const Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.isAnonymous == true ? '匿名ユーザー' : 'ユーザー',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${user?.uid?.substring(0, 8) ?? 'Unknown'}...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bioController,
                            maxLines: 3,
                            maxLength: 150,
                            decoration: const InputDecoration(
                              hintText: '自己紹介を入力してください',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                
                // 参加中のカウントダウンヘッダー
                Row(
                  children: [
                    const Text(
                      '参加中のカウントダウン',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isLoadingParticipants)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DA1F2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_participatedIds.length}',
                          style: const TextStyle(
                            color: Color(0xFF1DA1F2),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          // 参加中のカウントダウンリスト
          Expanded(
            child: _isLoadingParticipants
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('参加情報を読み込み中...'),
                      ],
                    ),
                  )
                : StreamBuilder<List<Countdown>>(
                    stream: SimpleStreamService.getCountdownsStream(limit: 50),
                    builder: (context, snapshot) {
                      print('SimpleProfileScreen - StreamBuilder state: ${snapshot.connectionState}');
                      print('SimpleProfileScreen - Has error: ${snapshot.hasError}');
                      print('SimpleProfileScreen - Data length: ${snapshot.data?.length ?? 0}');
                      
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text('エラーが発生しました'),
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

                      final allCountdowns = snapshot.data ?? [];
                      
                      // 参加中のカウントダウンのみをフィルタリング
                      final participatedCountdowns = allCountdowns
                          .where((countdown) => _participatedIds.contains(countdown.id))
                          .toList();
                      
                      // 残り時間順にソート
                      participatedCountdowns.sort((a, b) {
                        final now = DateTime.now();
                        final diffA = a.eventDate.difference(now);
                        final diffB = b.eventDate.difference(now);
                        
                        // 終了したイベントは後ろに
                        if (diffA.isNegative && !diffB.isNegative) return 1;
                        if (!diffA.isNegative && diffB.isNegative) return -1;
                        
                        // 残り時間が短い順
                        return diffA.compareTo(diffB);
                      });

                      print('SimpleProfileScreen - Participated countdowns: ${participatedCountdowns.length}');

                      if (participatedCountdowns.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                '参加しているカウントダウンがありません。\n詳細画面で参加者アイコンをタップして参加しましょう！',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: participatedCountdowns.length,
                        itemBuilder: (context, index) {
                          final countdown = participatedCountdowns[index];
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