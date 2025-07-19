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
    return Column(
      children: [
        // Tweet list
        Expanded(
          child: StreamBuilder<List<PostModel>>(
            stream: FirestoreService.getCasualPosts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // デバッグ情報
              print('カジュアル投稿データ: hasData=${snapshot.hasData}, '
                    'docsCount=${snapshot.data?.length ?? 0}');
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'まだカジュアル投稿がありません',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          // FloatingActionButtonと同じ機能を実現
                          Navigator.of(context).push(PageRouteBuilder(
                            opaque: false,
                            pageBuilder: (context, animation, secondaryAnimation) => 
                                const CasualPostModal(),
                          ));
                        },
                        child: const Text('最初の投稿をしてみる'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _showAllPosts(),
                        child: const Text('すべての投稿を確認（デバッグ）'),
                      ),
                    ],
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
      ],
    );
  }
}