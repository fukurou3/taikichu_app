import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'widgets/login_modal.dart';
import 'widgets/casual_post_modal.dart';
import 'widgets/serious_post_modal.dart';
import 'screens/casual_post_screen.dart';
import 'screens/serious_post_screen.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TwitterCloneApp());
}

class TwitterCloneApp extends StatelessWidget {
  const TwitterCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twitter Clone',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: GoogleFonts.inter().fontFamily,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  Future<void> _showLoginModal() async {
    await showDialog<bool>(
      context: context,
      builder: (context) => const LoginModal(),
    );
  }

  void _showPostModal() {
    if (_currentIndex == 0) {
      // カジュアル投稿モーダル
      showDialog(
        context: context,
        builder: (context) => const CasualPostModal(),
      );
    } else if (_currentIndex == 1) {
      // 真剣投稿モーダル
      showDialog(
        context: context,
        builder: (context) => const SeriousPostModal(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          StreamBuilder(
            stream: AuthService.authStateChanges,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => AuthService.signOut(),
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.login),
                  onPressed: () => _showLoginModal(),
                );
              }
            },
          ),
        ],
      ),
      body: _getBodyContent(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: '真剣投稿',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: '地図',
          ),
        ],
      ),
      floatingActionButton: _currentIndex != 2 ? FloatingActionButton(
        onPressed: _showPostModal,
        backgroundColor: _currentIndex == 0 ? Colors.blue : Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return 'ホーム';
      case 1:
        return '真剣投稿';
      case 2:
        return '地図';
      default:
        return 'ホーム';
    }
  }

  Widget _getBodyContent() {
    switch (_currentIndex) {
      case 0:
        return const CasualPostScreen();
      case 1:
        return const SeriousPostScreen();
      case 2:
        return const MapScreen();
      default:
        return const CasualPostScreen();
    }
  }
}