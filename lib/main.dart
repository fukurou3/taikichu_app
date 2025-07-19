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
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          enableFeedback: false,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xFF0F1419),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.grey.withOpacity(0.1),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFEFF3F4),
          ),
        ),
        centerTitle: false,
        actions: [
          StreamBuilder(
            stream: AuthService.authStateChanges,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: const Icon(Icons.logout_outlined),
                    onPressed: () => AuthService.signOut(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.grey[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                );
              } else {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: () => _showLoginModal(),
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('ログイン'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DA1F2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: _getBodyContent(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFEFF3F4), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: _currentIndex == 0 
              ? const Color(0xFF1DA1F2) 
              : _currentIndex == 1 
                  ? const Color(0xFFFF6B35)
                  : const Color(0xFF17BF63),
          unselectedItemColor: Colors.grey[600],
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: 12,
          ),
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'ホーム',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment),
              label: '真剣投稿',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: '地図',
            ),
          ],
        ),
      ),
      floatingActionButton: _currentIndex != 2 ? FloatingActionButton(
        onPressed: _showPostModal,
        backgroundColor: _currentIndex == 0 
            ? const Color(0xFF1DA1F2) 
            : const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, size: 28),
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