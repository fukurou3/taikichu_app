import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'dart:async';
import 'firebase_options.dart';

enum PostType { casual, serious }
enum LocationType { municipality, coordinates }

// 緯度経度クラス
class LatLng {
  final double latitude;
  final double longitude;
  
  const LatLng(this.latitude, this.longitude);
}

// 逆ジオコーディング: 座標から市区町村を特定
Future<String> getLocationFromCoordinates(double lat, double lng) async {
  try {
    // 国土地理院の逆ジオコーディングAPIを使用
    final url = 'https://mreversegeocoder.gsi.go.jp/reverse-geocoder/LonLatToAddress?lat=$lat&lon=$lng';
    
    final response = await html.HttpRequest.request(url);
    if (response.status == 200) {
      final data = json.decode(response.responseText!);
      if (data['results'] != null && data['results'].isNotEmpty) {
        final result = data['results'][0];
        final pref = result['prefecture'] ?? '';
        final city = result['city'] ?? '';
        final town = result['town'] ?? '';
        
        if (pref.isNotEmpty && city.isNotEmpty) {
          return '$pref$city${town.isNotEmpty ? town : ''}';
        }
      }
    }
  } catch (e) {
    print('逆ジオコーディングエラー: $e');
  }
  
  // フォールバック: 簡易的な地域判定
  return _getApproximateLocation(lat, lng);
}

// 簡易的な地域判定（フォールバック用）
String _getApproximateLocation(double lat, double lng) {
  // 北海道
  if (lat >= 41.0) return '北海道';
  
  // 沖縄
  if (lat <= 26.5) return '沖縄県';
  
  // 東北地方
  if (lat >= 38.0) {
    if (lng <= 140.0) return '秋田県';
    if (lng <= 141.0) return '岩手県';
    return '宮城県';
  }
  
  // 関東地方
  if (lat >= 35.5) {
    if (lng <= 139.0) return '群馬県';
    if (lng <= 140.0) return '埼玉県';
    return '千葉県';
  }
  
  // 中部地方
  if (lat >= 34.5) {
    if (lng <= 137.0) return '石川県';
    if (lng <= 138.0) return '長野県';
    if (lng <= 139.0) return '静岡県';
    return '神奈川県';
  }
  
  // 関西地方
  if (lat >= 33.5) {
    if (lng <= 135.0) return '兵庫県';
    if (lng <= 136.0) return '大阪府';
    return '三重県';
  }
  
  // 中国・四国地方
  if (lat >= 32.5) {
    if (lng <= 132.0) return '山口県';
    if (lng <= 134.0) return '愛媛県';
    return '香川県';
  }
  
  // 九州地方
  if (lng <= 130.0) return '熊本県';
  if (lng <= 131.0) return '大分県';
  return '福岡県';
}

// 日本の主要市区町村データ（サンプル）
final List<String> japanMunicipalities = [
  '北海道札幌市',
  '青森県青森市',
  '岩手県盛岡市',
  '宮城県仙台市',
  '秋田県秋田市',
  '山形県山形市',
  '福島県福島市',
  '茨城県水戸市',
  '栃木県宇都宮市',
  '群馬県前橋市',
  '埼玉県さいたま市',
  '千葉県千葉市',
  '東京都千代田区',
  '東京都中央区',
  '東京都港区',
  '東京都新宿区',
  '東京都文京区',
  '東京都台東区',
  '東京都墨田区',
  '東京都江東区',
  '東京都品川区',
  '東京都目黒区',
  '東京都大田区',
  '東京都世田谷区',
  '東京都渋谷区',
  '東京都中野区',
  '東京都杉並区',
  '東京都豊島区',
  '東京都北区',
  '東京都荒川区',
  '東京都板橋区',
  '東京都練馬区',
  '東京都足立区',
  '東京都葛飾区',
  '東京都江戸川区',
  '神奈川県横浜市',
  '神奈川県川崎市',
  '新潟県新潟市',
  '富山県富山市',
  '石川県金沢市',
  '福井県福井市',
  '山梨県甲府市',
  '長野県長野市',
  '岐阜県岐阜市',
  '静岡県静岡市',
  '愛知県名古屋市',
  '三重県津市',
  '滋賀県大津市',
  '京都府京都市',
  '大阪府大阪市',
  '兵庫県神戸市',
  '奈良県奈良市',
  '和歌山県和歌山市',
  '鳥取県鳥取市',
  '島根県松江市',
  '岡山県岡山市',
  '広島県広島市',
  '山口県山口市',
  '徳島県徳島市',
  '香川県高松市',
  '愛媛県松山市',
  '高知県高知市',
  '福岡県福岡市',
  '佐賀県佐賀市',
  '長崎県長崎市',
  '熊本県熊本市',
  '大分県大分市',
  '宮崎県宮崎市',
  '鹿児島県鹿児島市',
  '沖縄県那覇市',
];

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
        textTheme: GoogleFonts.interTextTheme(),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AuthWrapper(),
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

class LoginModal extends StatefulWidget {
  const LoginModal({super.key});

  @override
  State<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends State<LoginModal> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ログインに失敗しました: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('サインアップに失敗しました: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSignUp ? 'アカウントを作成' : 'ログイン',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isSignUp)
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名前',
                  border: OutlineInputBorder(),
                ),
              ),
            if (_isSignUp) const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'パスワード',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : (_isSignUp ? _signUp : _signIn),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isSignUp ? 'サインアップ' : 'ログイン'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _isSignUp = !_isSignUp),
              child: Text(
                _isSignUp ? 'すでにアカウントをお持ちですか？ログイン' : 'アカウントを作成',
                style: TextStyle(color: Colors.blue[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => FirebaseAuth.instance.signOut(),
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

// カジュアル投稿画面
class CasualPostScreen extends StatefulWidget {
  const CasualPostScreen({super.key});

  @override
  State<CasualPostScreen> createState() => _CasualPostScreenState();
}

class _CasualPostScreenState extends State<CasualPostScreen> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tweet list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .where('type', isEqualTo: 'casual')
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // デバッグ情報
              print('カジュアル投稿データ: hasData=${snapshot.hasData}, docsCount=${snapshot.data?.docs.length ?? 0}');
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final post = snapshot.data!.docs[index];
                  final data = post.data() as Map<String, dynamic>;
                  final timestamp = data['createdAt'] as Timestamp?;
                  
                  return Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey, width: 0.5),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: const Icon(Icons.person, color: Colors.blue),
                      ),
                      title: Row(
                        children: [
                          Text(
                            data['authorName'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          if (timestamp != null)
                            Text(
                              _formatTimestamp(timestamp),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          data['content'] ?? '',
                          style: const TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAllPosts() async {
    try {
      final allPostsQuery = await FirebaseFirestore.instance
          .collection('posts')
          .limit(50)
          .get();
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            width: 500,
            height: 600,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'すべての投稿 (${allPostsQuery.docs.length}件)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: allPostsQuery.docs.length,
                    itemBuilder: (context, index) {
                      final data = allPostsQuery.docs[index].data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            data['type'] == 'casual' ? Icons.chat_bubble : Icons.assignment,
                            color: data['type'] == 'casual' ? Colors.blue : Colors.orange,
                          ),
                          title: Text(
                            data['title'] ?? data['content']?.substring(0, 30) ?? 'タイトルなし',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('タイプ: ${data['type'] ?? 'unknown'}'),
                              Text('投稿者: ${data['authorName'] ?? 'Unknown'}'),
                              if (data.containsKey('municipality'))
                                Text('場所: ${data['municipality']}'),
                              if (data.containsKey('latitude'))
                                Text('座標: ${data['latitude']}, ${data['longitude']}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}秒前';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}時間前';
    } else {
      return '${difference.inDays}日前';
    }
  }
}

// 真剣投稿画面
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
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .where('type', isEqualTo: 'serious')
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // デバッグ情報
              print('真剣投稿データ: hasData=${snapshot.hasData}, docsCount=${snapshot.data?.docs.length ?? 0}');
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final post = snapshot.data!.docs[index];
                  final data = post.data() as Map<String, dynamic>;
                  final timestamp = data['createdAt'] as Timestamp?;
                  
                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.orange[100],
                                child: const Icon(Icons.assignment, color: Colors.orange),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['authorName'] ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    if (timestamp != null)
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            data['title'] ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['content'] ?? '',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          
                          // 位置情報表示
                          if (data.containsKey('municipality'))
                            Row(
                              children: [
                                const Icon(Icons.location_city, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  data['municipality'],
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            )
                          else if (data.containsKey('latitude') && data.containsKey('longitude'))
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      '詳細位置指定',
                                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                                    ),
                                  ],
                                ),
                                if (data.containsKey('detectedLocation'))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 20, top: 2),
                                    child: Text(
                                      '(${data['detectedLocation']})',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }


  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}秒前';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}時間前';
    } else {
      return '${difference.inDays}日前';
    }
  }
}

// 地図画面
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late String viewId;
  List<DocumentSnapshot> allPosts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    viewId = 'map-view-${DateTime.now().millisecondsSinceEpoch}';
    _initializeMap();
    _loadPosts();
  }

  void _initializeMap() {
    // 国土地理院の地図HTMLを作成
    final mapHtml = '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>地図</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: 100vh; width: 100vw; }
            .custom-popup {
                max-width: 300px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            }
            .popup-title {
                font-weight: bold;
                font-size: 16px;
                margin-bottom: 8px;
                color: #333;
            }
            .popup-content {
                font-size: 14px;
                margin-bottom: 8px;
                color: #666;
            }
            .popup-location {
                font-size: 12px;
                color: #888;
                display: flex;
                align-items: center;
            }
            .popup-author {
                font-size: 12px;
                color: #888;
                margin-top: 4px;
            }
        </style>
    </head>
    <body>
        <div id="map"></div>
        <script>
            // 地図の初期化（東京を中心に）
            var map = L.map('map').setView([35.6762, 139.6503], 10);
            
            // 国土地理院の標準地図タイル
            L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png', {
                attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">国土地理院</a>',
                maxZoom: 18
            }).addTo(map);
            
            // 投稿データを表示するためのマーカーグループ
            var markersGroup = L.layerGroup().addTo(map);
            
            // Flutterからのメッセージを受信
            window.addEventListener('message', function(event) {
                if (event.data.type === 'addMarkers') {
                    markersGroup.clearLayers();
                    event.data.posts.forEach(function(post) {
                        if (post.latitude && post.longitude) {
                            var marker = L.marker([post.latitude, post.longitude])
                                .bindPopup(createPopupContent(post));
                            markersGroup.addLayer(marker);
                        }
                    });
                }
            });
            
            function createPopupContent(post) {
                var title = post.title || post.content.substring(0, 50) + '...';
                var content = post.content;
                var author = post.authorName || 'Unknown';
                var location = '';
                
                if (post.municipality) {
                    location = '📍 ' + post.municipality;
                } else if (post.latitude && post.longitude) {
                    if (post.detectedLocation) {
                        location = '📍 ' + post.detectedLocation + ' (詳細位置)';
                    } else {
                        location = '📍 ' + post.latitude.toFixed(4) + ', ' + post.longitude.toFixed(4);
                    }
                }
                
                return '<div class="custom-popup">' +
                       '<div class="popup-title">' + title + '</div>' +
                       '<div class="popup-content">' + content + '</div>' +
                       '<div class="popup-location">' + location + '</div>' +
                       '<div class="popup-author">投稿者: ' + author + '</div>' +
                       '</div>';
            }
            
            // 地図クリック時の処理（位置選択用）
            map.on('click', function(e) {
                window.parent.postMessage({
                    type: 'mapClicked',
                    lat: e.latlng.lat,
                    lng: e.latlng.lng
                }, '*');
            });
        </script>
    </body>
    </html>
    ''';

    // HTMLビューを登録
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int id) {
        final iframe = html.IFrameElement()
          ..width = '100%'
          ..height = '100%'
          ..srcdoc = mapHtml
          ..style.border = 'none';
        return iframe;
      },
    );
  }

  void _loadPosts() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .limit(100)
          .get();
      
      setState(() {
        allPosts = querySnapshot.docs;
        isLoading = false;
      });
      
      _updateMapMarkers();
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _updateMapMarkers() {
    final postsWithLocation = allPosts.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data.containsKey('latitude') && data.containsKey('longitude');
    }).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'title': data['title'],
        'content': data['content'],
        'authorName': data['authorName'],
        'municipality': data['municipality'],
        'latitude': data['latitude'],
        'longitude': data['longitude'],
      };
    }).toList();

    print('地図に表示する投稿数: ${postsWithLocation.length}');

    // 少し遅延してからメッセージを送信
    Future.delayed(const Duration(milliseconds: 500), () {
      html.window.postMessage({
        'type': 'addMarkers',
        'posts': postsWithLocation,
      }, '*');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 地図コントロール
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadPosts,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('更新'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showLocationPosts('casual'),
                  icon: const Icon(Icons.chat_bubble, size: 16),
                  label: const Text('カジュアル'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[400],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showLocationPosts('serious'),
                  icon: const Icon(Icons.assignment, size: 16),
                  label: const Text('真剣投稿'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // 地図表示
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : HtmlElementView(viewType: viewId),
          ),
          
          // 投稿数表示
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: Text(
              '位置情報付き投稿: ${allPosts.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data.containsKey('latitude') && data.containsKey('longitude');
              }).length}件',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationPosts(String type) async {
    final posts = await FirebaseFirestore.instance
        .collection('posts')
        .where('type', isEqualTo: type)
        .limit(50)
        .get();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                '${type == 'casual' ? 'カジュアル' : '真剣'}投稿一覧',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: posts.docs.length,
                  itemBuilder: (context, index) {
                    final data = posts.docs[index].data() as Map<String, dynamic>;
                    final hasLocation = data.containsKey('latitude') || data.containsKey('municipality');
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          hasLocation ? Icons.location_on : Icons.location_off,
                          color: hasLocation ? Colors.green : Colors.grey,
                        ),
                        title: Text(
                          data['title'] ?? data['content']?.substring(0, 30) ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['authorName'] ?? 'Unknown',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (data.containsKey('municipality'))
                              Text(
                                '📍 ${data['municipality']}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              )
                            else if (data.containsKey('latitude'))
                              Text(
                                '📍 ${data['latitude'].toFixed(3)}, ${data['longitude'].toFixed(3)}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 地図選択ウィジェット
class MapPickerWidget extends StatefulWidget {
  final Function(double lat, double lng) onLocationSelected;
  
  const MapPickerWidget({super.key, required this.onLocationSelected});

  @override
  State<MapPickerWidget> createState() => _MapPickerWidgetState();
}

class _MapPickerWidgetState extends State<MapPickerWidget> {
  late String viewId;

  @override
  void initState() {
    super.initState();
    viewId = 'map-picker-${DateTime.now().millisecondsSinceEpoch}';
    _initializeMapPicker();
  }

  void _initializeMapPicker() {
    final mapHtml = '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>位置選択</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: 100vh; width: 100vw; cursor: crosshair; }
        </style>
    </head>
    <body>
        <div id="map"></div>
        <script>
            var map = L.map('map').setView([35.6762, 139.6503], 10);
            
            L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png', {
                attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">国土地理院</a>',
                maxZoom: 18
            }).addTo(map);
            
            var selectedMarker = null;
            
            map.on('click', function(e) {
                if (selectedMarker) {
                    map.removeLayer(selectedMarker);
                }
                
                selectedMarker = L.marker([e.latlng.lat, e.latlng.lng])
                    .addTo(map)
                    .bindPopup('選択された位置<br>緯度: ' + e.latlng.lat.toFixed(4) + '<br>経度: ' + e.latlng.lng.toFixed(4))
                    .openPopup();
                
                // Flutterに位置情報を送信
                window.parent.postMessage({
                    type: 'locationSelected',
                    lat: e.latlng.lat,
                    lng: e.latlng.lng
                }, '*');
            });
        </script>
    </body>
    </html>
    ''';

    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int id) {
        final iframe = html.IFrameElement()
          ..width = '100%'
          ..height = '100%'
          ..srcdoc = mapHtml
          ..style.border = 'none';
        
        // メッセージリスナーを追加
        html.window.addEventListener('message', (event) {
          final data = (event as html.MessageEvent).data;
          if (data != null && data['type'] == 'locationSelected') {
            widget.onLocationSelected(data['lat'], data['lng']);
          }
        });
        
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewId);
  }
}

// カジュアル投稿モーダル
class CasualPostModal extends StatefulWidget {
  const CasualPostModal({super.key});

  @override
  State<CasualPostModal> createState() => _CasualPostModalState();
}

class _CasualPostModalState extends State<CasualPostModal> {
  final _tweetController = TextEditingController();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _tweetController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tweetController.dispose();
    super.dispose();
  }

  Future<void> _showLoginModal() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const LoginModal(),
    );
    
    if (result == true) {
      _postTweet();
    }
  }

  Future<void> _postTweet() async {
    if (_tweetController.text.trim().isEmpty) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginModal();
      return;
    }
    
    setState(() => _isPosting = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      await FirebaseFirestore.instance.collection('posts').add({
        'type': 'casual',
        'content': _tweetController.text.trim(),
        'authorId': user.uid,
        'authorName': userDoc.data()?['name'] ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      _tweetController.clear();
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('投稿しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投稿に失敗しました: ${e.toString()}')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'つぶやく',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snapshot) {
                    return CircleAvatar(
                      backgroundColor: snapshot.hasData ? Colors.blue[100] : Colors.grey[300],
                      child: Icon(
                        Icons.person, 
                        color: snapshot.hasData ? Colors.blue : Colors.grey,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      StreamBuilder<User?>(
                        stream: FirebaseAuth.instance.authStateChanges(),
                        builder: (context, snapshot) {
                          return TextField(
                            controller: _tweetController,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: snapshot.hasData ? 'いまどうしてる？' : 'ツイートするにはログインしてください',
                              border: const OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 16),
                            onTap: snapshot.hasData ? null : _showLoginModal,
                            readOnly: !snapshot.hasData,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${280 - _tweetController.text.length}',
                            style: TextStyle(
                              color: _tweetController.text.length > 280 
                                  ? Colors.red 
                                  : Colors.grey,
                            ),
                          ),
                          StreamBuilder<User?>(
                            stream: FirebaseAuth.instance.authStateChanges(),
                            builder: (context, snapshot) {
                              final isLoggedIn = snapshot.hasData;
                              final hasText = _tweetController.text.trim().isNotEmpty;
                              
                              return ElevatedButton(
                                onPressed: (_isPosting || !hasText) ? null : _postTweet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: (isLoggedIn && hasText) ? Colors.blue[600] : Colors.grey[400],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                child: _isPosting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(isLoggedIn ? 'ツイート' : 'ログインして投稿'),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 真剣投稿モーダル
class SeriousPostModal extends StatefulWidget {
  const SeriousPostModal({super.key});

  @override
  State<SeriousPostModal> createState() => _SeriousPostModalState();
}

class _SeriousPostModalState extends State<SeriousPostModal> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isPosting = false;
  
  String? _selectedMunicipality;
  LocationType _locationType = LocationType.municipality;
  LatLng? _selectedCoordinates;
  String? _detectedLocation;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _showLoginModal() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const LoginModal(),
    );
    
    if (result == true) {
      _postSerious();
    }
  }

  Future<void> _postSerious() async {
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルと内容を入力してください')),
      );
      return;
    }
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginModal();
      return;
    }
    
    setState(() => _isPosting = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final postData = {
        'type': 'serious',
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'authorId': user.uid,
        'authorName': userDoc.data()?['name'] ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'locationType': _locationType.toString(),
      };

      if (_locationType == LocationType.municipality && _selectedMunicipality != null) {
        postData['municipality'] = _selectedMunicipality!;
      } else if (_locationType == LocationType.coordinates && _selectedCoordinates != null) {
        postData['latitude'] = _selectedCoordinates!.latitude;
        postData['longitude'] = _selectedCoordinates!.longitude;
        if (_detectedLocation != null) {
          postData['detectedLocation'] = _detectedLocation!;
        }
      }
      
      await FirebaseFirestore.instance.collection('posts').add(postData);
      
      _titleController.clear();
      _contentController.clear();
      setState(() {
        _selectedMunicipality = null;
        _selectedCoordinates = null;
        _detectedLocation = null;
        _locationType = LocationType.municipality;
      });

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('投稿しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投稿に失敗しました: ${e.toString()}')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  void _showMapPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 600,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('地図で位置を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '地図をクリックして位置を選択してください',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MapPickerWidget(
                      onLocationSelected: (lat, lng) async {
                        setState(() {
                          _selectedCoordinates = LatLng(lat, lng);
                          _detectedLocation = null;
                        });
                        Navigator.pop(context);
                        
                        // 住所を自動検出
                        try {
                          final location = await getLocationFromCoordinates(lat, lng);
                          setState(() {
                            _detectedLocation = location;
                          });
                          print('検出された住所: $location');
                        } catch (e) {
                          print('住所検出エラー: $e');
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '真剣投稿',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snapshot) {
                    final isLoggedIn = snapshot.hasData;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: isLoggedIn ? 'タイトル（例：○○の仲間募集、△△の課題報告）' : 'ログインして投稿',
                            border: const OutlineInputBorder(),
                            labelText: 'タイトル',
                          ),
                          onTap: isLoggedIn ? null : _showLoginModal,
                          readOnly: !isLoggedIn,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _contentController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: isLoggedIn ? '詳細な内容を記入してください' : 'ログインして投稿',
                            border: const OutlineInputBorder(),
                            labelText: '内容',
                          ),
                          onTap: isLoggedIn ? null : _showLoginModal,
                          readOnly: !isLoggedIn,
                        ),
                        const SizedBox(height: 16),
                        
                        // 位置情報選択
                        if (isLoggedIn) ...[
                          Text('位置情報', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<LocationType>(
                                  title: const Text('市区町村'),
                                  value: LocationType.municipality,
                                  groupValue: _locationType,
                                  onChanged: (value) {
                                    setState(() {
                                      _locationType = value!;
                                      _selectedCoordinates = null;
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<LocationType>(
                                  title: const Text('詳細位置'),
                                  value: LocationType.coordinates,
                                  groupValue: _locationType,
                                  onChanged: (value) {
                                    setState(() {
                                      _locationType = value!;
                                      _selectedMunicipality = null;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          
                          if (_locationType == LocationType.municipality)
                            DropdownSearch<String>(
                              items: japanMunicipalities,
                              selectedItem: _selectedMunicipality,
                              onChanged: (value) {
                                setState(() {
                                  _selectedMunicipality = value;
                                });
                              },
                              dropdownDecoratorProps: const DropDownDecoratorProps(
                                dropdownSearchDecoration: InputDecoration(
                                  labelText: '市区町村を選択',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: const TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: '検索...',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showMapPicker(),
                                  icon: const Icon(Icons.map),
                                  label: Text(_selectedCoordinates == null 
                                      ? '地図で位置を選択' 
                                      : '位置選択済み'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _selectedCoordinates == null 
                                        ? Colors.grey[400] 
                                        : Colors.green,
                                  ),
                                ),
                                if (_selectedCoordinates != null && _detectedLocation != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        border: Border.all(color: Colors.blue[200]!),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on, size: 16, color: Colors.blue[600]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '特定された地域: $_detectedLocation',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue[800],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                        
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (isLoggedIn && 
                                       _titleController.text.trim().isNotEmpty && 
                                       _contentController.text.trim().isNotEmpty && 
                                       !_isPosting) 
                                ? _postSerious 
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isPosting
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(isLoggedIn ? '真剣投稿' : 'ログインして投稿'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}