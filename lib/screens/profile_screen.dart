import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/optimized_stream_service.dart';
import '../services/scalable_participant_service.dart';
import '../services/timeline_stream_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import '../models/countdown.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _bioController = TextEditingController();
  List<String> _participatedIds = [];
  bool _isLoadingParticipants = true;
  
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
        });
      }
    } catch (e) {
      // エラー時は空リストを表示
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
    
    return Container(
      color: Colors.white,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
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
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('設定'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('設定画面は準備中です')),
                      );
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '参加中のカウントダウン',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(width: 8),
                      if (!_isLoadingParticipants)
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
          ),
          _isLoadingParticipants
              ? const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              : StreamBuilder<List<Countdown>>(
                  stream: TimelineStreamService.getPersonalTimelineStream(
                    limit: 50,
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

                    final participatedCountdowns = snapshot.data ?? [];
                    
                    if (participatedCountdowns.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              '参加しているカウントダウンがありません。\n詳細画面で参加者アイコンをタップして参加しましょう！',
                              textAlign: TextAlign.center,
                              style: TextStyle(
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
                          final countdown = participatedCountdowns[index];
                          
                          return EnhancedCountdownCard(countdown: countdown);
                        },
                        childCount: participatedCountdowns.length,
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}