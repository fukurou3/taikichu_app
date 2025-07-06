// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/simple_home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/simple_profile_screen.dart';
import 'screens/create_countdown_screen.dart';
import 'screens/countdown_search_screen.dart';

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
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
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
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const SimpleHomeScreen(),
    const SearchScreen(),
    const NotificationsScreen(),
    const SimpleProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _screens[_selectedIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '',
          ),
        ],
      ),
    );
  }
}