import 'package:flutter/material.dart';
import '../models/post_models.dart';
import '../services/firestore_service.dart';
import '../widgets/post_card.dart';

class SeriousPostScreen extends StatefulWidget {
  const SeriousPostScreen({super.key});

  @override
  State<SeriousPostScreen> createState() => _SeriousPostScreenState();
}

class _SeriousPostScreenState extends State<SeriousPostScreen> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 投稿一覧
        Expanded(
          child: StreamBuilder<List<PostModel>>(
            stream: FirestoreService.getSeriousPosts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // デバッグ情報
              print('真剣投稿データ: hasData=${snapshot.hasData}, '
                    'docsCount=${snapshot.data?.length ?? 0}');
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'まだ真剣投稿がありません',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '地域の課題や仲間募集を投稿してみましょう',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
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