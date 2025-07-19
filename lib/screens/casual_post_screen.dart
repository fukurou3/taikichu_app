import 'package:flutter/material.dart';
import '../models/post_models.dart';
import '../services/firestore_service.dart';
import '../widgets/post_card.dart';
import '../widgets/casual_post_modal.dart';

class CasualPostScreen extends StatefulWidget {
  const CasualPostScreen({super.key});

  @override
  State<CasualPostScreen> createState() => _CasualPostScreenState();
}

class _CasualPostScreenState extends State<CasualPostScreen> {
  final _scrollController = ScrollController();

  Future<void> _showAllPosts() async {
    try {
      final posts = await FirestoreService.getAllPosts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('全投稿数: ${posts.length}件（デバッグ情報）')),
        );
        
        for (final post in posts.take(3)) {
          print('投稿: ${post.content} (タイプ: ${post.type})');
        }
      }
    } catch (e) {
      print('デバッグ情報取得エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Tweet list
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: StreamBuilder<List<PostModel>>(
                  stream: FirestoreService.getCasualPosts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF1DA1F2),
                        ),
                      );
                    }
                    
                    // デバッグ情報
                    print('カジュアル投稿データ: hasData=${snapshot.hasData}, '
                          'docsCount=${snapshot.data?.length ?? 0}');
                    
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[100],
                                ),
                                child: Icon(
                                  Icons.chat_bubble_outline,
                                  size: 32,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'まだ投稿がありません',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '最初の投稿をしてみましょう',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(PageRouteBuilder(
                                    opaque: false,
                                    pageBuilder: (context, animation, secondaryAnimation) => 
                                        const CasualPostModal(),
                                  ));
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1DA1F2),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                child: const Text(
                                  '投稿する',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => _showAllPosts(),
                                child: Text(
                                  'すべての投稿を確認（デバッグ）',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final post = snapshot.data![index];
                        return PostCard(post: post);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}