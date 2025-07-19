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
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 投稿一覧
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: StreamBuilder<List<PostModel>>(
                  stream: FirestoreService.getSeriousPosts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF6B35),
                        ),
                      );
                    }
                    
                    // デバッグ情報
                    print('真剣投稿データ: hasData=${snapshot.hasData}, '
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
                                  color: Colors.orange[50],
                                ),
                                child: Icon(
                                  Icons.assignment_outlined,
                                  size: 32,
                                  color: Colors.orange[400],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'まだ真剣投稿がありません',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '地域の課題や仲間募集を投稿してみましょう',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
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