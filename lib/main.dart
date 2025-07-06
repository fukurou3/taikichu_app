// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/create_countdown_screen.dart';
import 'screens/trend_ranking_screen.dart';
import 'services/countdown_service.dart';
import 'services/trend_ranking_service.dart';
import 'widgets/countdown_card.dart';
import 'widgets/trend_ranking_card.dart';
import 'models/countdown.dart';
import 'models/trend_ranking.dart';

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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // トレンドランキングセクション
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'トレンドランキング',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
                  const SizedBox(height: 8),
                  FutureBuilder<List<TrendRanking>>(
                    future: TrendRankingService.getTrendRankings(limit: 3),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text('エラーが発生しました: ${snapshot.error}'),
                        );
                      }

                      final rankings = snapshot.data ?? [];

                      if (rankings.isEmpty) {
                        return const Center(
                          child: Text(
                            'ランキングデータがありません',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return Column(
                        children: rankings.map((ranking) {
                          return TrendRankingCard(
                            ranking: ranking,
                            showRank: true,
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // カウントダウン一覧セクション
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text(
                'すべてのカウントダウン',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Countdown>>(
              stream: CountdownService.getCountdownsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('エラーが発生しました: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final countdowns = snapshot.data ?? [];

                if (countdowns.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'まだカウントダウンがありません。\n右下のボタンから作成しましょう！',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: countdowns.length,
                  itemBuilder: (context, index) {
                    return CountdownCard(countdown: countdowns[index]);
                  },
                );
              },
            ),
          ],
        ),
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