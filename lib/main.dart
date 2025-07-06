// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/create_countdown_screen.dart';
import 'screens/thread_screen.dart';
import 'screens/trend_ranking_screen.dart';
import 'services/countdown_service.dart';
import 'services/trend_ranking_service.dart';
import 'services/optimized_stream_service.dart';
import 'widgets/countdown_card.dart';
import 'widgets/trend_ranking_card.dart';
import 'widgets/paginated_countdown_list.dart';
import 'models/countdown.dart';
import 'models/trend_ranking.dart';
import 'models/ranking_item.dart';

void main() async { // main関数を非同期 (async) に変更
  // Flutterエンジンのバインディングが初期化されるのを確実にする
  WidgetsFlutterBinding.ensureInitialized(); 

  // Firebaseの初期化
  // これにより、アプリがFirebaseプロジェクトに接続されます
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 匿名認証でログイン (開発中のテスト用、本番では別の認証方法を実装します)
  // FirebaseコンソールでAuthenticationの「匿名」プロバイダを有効にする必要があります。
  try {
    await FirebaseAuth.instance.signInAnonymously();
    print("Signed in anonymously."); // 匿名ログインが成功したことをコンソールに出力
  } catch (e) {
    print("Error signing in anonymously: $e"); // エラーが発生した場合はコンソールに出力
  }

  // アプリケーションを実行
  runApp(const MyApp());
}

// ここから下のMyAppクラスとMyHomePageクラスは、
// flutter create で自動生成されたデフォルトのコードのままでOKです。
// アプリ名だけ『待機中。』に変更しておくと良いでしょう。

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '待機中。', // アプリ名を『待機中。』に変更
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: '待機中。'), // アプリ名を『待機中。』に変更
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  
  Widget _buildCountdownText(DateTime eventDate) {
    final now = DateTime.now();
    final difference = eventDate.difference(now);
    
    if (difference.isNegative) {
      return const Text(
        'イベント終了',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      );
    }
    
    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    
    String countdownText;
    if (days > 0) {
      countdownText = 'あと${days}日 ${hours}時間';
    } else if (hours > 0) {
      countdownText = 'あと${hours}時間 ${minutes}分';
    } else if (minutes > 0) {
      countdownText = 'あと${minutes}分';
    } else {
      countdownText = 'まもなく開始！';
    }
    
    return Text(
      countdownText,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.trending_up),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TrendRankingScreen()),
              );
            },
            tooltip: 'トレンドランキング',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // トレンドランキングのセクション
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '人気のカウントダウン',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TrendRankingScreen()),
                      );
                    },
                    child: const Text('すべて見る'),
                  ),
                ],
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('trendRankings')
                .where('category', isEqualTo: 'overall')
                .orderBy('rank')
                .limit(3)
                .snapshots(),
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
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('まだトレンドはありません。')),
                );
              }

              final rankingDocs = snapshot.data!.docs;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = rankingDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      elevation: 2.0,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index == 0 ? Colors.amber : 
                                          index == 1 ? Colors.grey[400] :
                                          Colors.brown[300],
                          child: Text('${index + 1}'),
                        ),
                        title: Text(data['eventName'] ?? ''),
                        subtitle: Text('カテゴリ: ${data['category'] ?? ''} | スコア: ${data['trendScore']?.toInt() ?? 0}'),
                        onTap: () async {
                          final countdownId = data['countdownId'];
                          if (countdownId != null) {
                            final countdownDoc = await FirebaseFirestore.instance
                                .collection('counts')
                                .doc(countdownId)
                                .get();
                            if (countdownDoc.exists) {
                              final originalCountdown = Countdown.fromFirestore(countdownDoc, null);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ThreadScreen(countdown: originalCountdown),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('元のカウントダウンが見つかりません。')),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                  childCount: rankingDocs.length,
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: const Divider(height: 30, thickness: 2, indent: 16, endIndent: 16),
          ),
          // 既存のカウントダウン一覧のセクション
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '全てのカウントダウン',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('counts')
                .orderBy('eventDate', descending: false)
                .snapshots(),
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
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Text(
                      'まだカウントダウンがありません。\n右下のボタンから作成しましょう！',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                );
              }

              final countdownDocs = snapshot.data!.docs;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = countdownDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final countdown = Countdown(
                      id: doc.id,
                      eventName: data['eventName'] ?? '',
                      eventDate: (data['eventDate'] as Timestamp).toDate(),
                      category: data['category'] ?? '',
                      creatorId: data['creatorId'] ?? '',
                      participantsCount: data['participantsCount'] ?? 0,
                      likesCount: data['likesCount'] ?? 0,
                      commentsCount: data['commentsCount'] ?? 0,
                    );
                    
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ThreadScreen(countdown: countdown)),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                        elevation: 4.0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                countdown.eventName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'イベント日時: ${countdown.eventDate.toLocal().toString().split(' ')[0]}',
                                style: const TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                              Text(
                                'カテゴリ: ${countdown.category}',
                                style: const TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              _buildCountdownText(countdown.eventDate),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  '${countdown.participantsCount} 人が待機中',
                                  style: const TextStyle(fontSize: 14, color: Colors.blue),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.comment_outlined, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${countdown.commentsCount} コメント',
                                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(Icons.favorite_border, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${countdown.likesCount}',
                                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: countdownDocs.length,
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateCountdownScreen()),
          );
        },
        tooltip: '新しいカウントダウンを作成',
        child: const Icon(Icons.add),
      ),
    );
  }
}