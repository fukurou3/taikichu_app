// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/create_countdown_screen.dart';
import 'screens/countdown_search_screen.dart';
import 'screens/thread_screen.dart';
import 'screens/trend_ranking_screen.dart';
import 'services/countdown_service.dart';
import 'services/trend_ranking_service.dart';
import 'services/optimized_stream_service.dart';
import 'widgets/countdown_card.dart';
import 'widgets/enhanced_countdown_card.dart';
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
          FutureBuilder<List<TrendRanking>>(
            future: TrendRankingService.getTrendRankings(
              type: RankingType.overall,
              limit: 3,
            ),
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

              final rankings = snapshot.data ?? [];
              
              if (rankings.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('まだトレンドはありません。')),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final ranking = rankings[index];
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      elevation: 2.0,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index == 0 ? Colors.amber : 
                                          index == 1 ? Colors.grey[400] :
                                          Colors.brown[300],
                          child: Text('${ranking.rank}'),
                        ),
                        title: Text(ranking.eventName),
                        subtitle: Text('カテゴリ: ${ranking.category} | スコア: ${ranking.trendScore.toInt()}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people, size: 16, color: Colors.grey[600]),
                            Text(' ${ranking.participantsCount}'),
                            const SizedBox(width: 8),
                            Icon(Icons.comment, size: 16, color: Colors.grey[600]),
                            Text(' ${ranking.commentsCount}'),
                            const SizedBox(width: 8),
                            Icon(Icons.favorite, size: 16, color: Colors.red[400]),
                            Text(' ${ranking.participantsCount}'),
                          ],
                        ),
                        onTap: () {
                          final countdown = Countdown(
                            id: ranking.countdownId,
                            eventName: ranking.eventName,
                            eventDate: ranking.eventDate,
                            category: ranking.category,
                            creatorId: '',
                            participantsCount: ranking.participantsCount,
                            commentsCount: ranking.commentsCount,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ThreadScreen(countdown: countdown),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  childCount: rankings.length,
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
                      'まだカウントダウンがありません。\n右下のボタンから作成しましょう！',
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CountdownSearchScreen()),
          );
        },
        tooltip: '新しいカウントダウンを作成',
        child: const Icon(Icons.add),
      ),
    );
  }
}