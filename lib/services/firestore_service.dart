import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_models.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // カジュアル投稿の取得
  static Stream<List<PostModel>> getCasualPosts({int limit = 50}) {
    return _firestore
        .collection('posts')
        .where('type', isEqualTo: 'casual')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostModel.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  // 真剣投稿の取得
  static Stream<List<PostModel>> getSeriousPosts({int limit = 50}) {
    return _firestore
        .collection('posts')
        .where('type', isEqualTo: 'serious')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostModel.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  // 位置情報付き投稿の取得（地図用）
  static Future<List<PostModel>> getPostsWithLocation() async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('posts')
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc.id, doc.data() as Map<String, dynamic>))
          .where((post) => post.hasLocation)
          .toList();
    } catch (e) {
      print('位置情報付き投稿の取得エラー: $e');
      return [];
    }
  }

  // 投稿の作成
  static Future<void> createPost(PostModel post) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('ユーザーがログインしていません');

    // ユーザー情報を取得
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userName = userDoc.data()?['name'] ?? 'Unknown';

    // 投稿データを作成
    final postData = post.toFirestore();
    postData['authorId'] = user.uid;
    postData['authorName'] = userName;
    postData['createdAt'] = FieldValue.serverTimestamp();

    await _firestore.collection('posts').add(postData);
  }

  // カジュアル投稿の作成
  static Future<void> createCasualPost(String content) async {
    final post = PostModel(
      id: '',
      type: PostType.casual,
      content: content,
      authorId: '',
      authorName: '',
      createdAt: DateTime.now(),
    );
    await createPost(post);
  }

  // 真剣投稿の作成
  static Future<void> createSeriousPost({
    required String title,
    required String content,
    LocationType? locationType,
    String? municipality,
    double? latitude,
    double? longitude,
    String? detectedLocation,
  }) async {
    final post = PostModel(
      id: '',
      type: PostType.serious,
      content: content,
      title: title,
      authorId: '',
      authorName: '',
      createdAt: DateTime.now(),
      locationType: locationType,
      municipality: municipality,
      latitude: latitude,
      longitude: longitude,
      detectedLocation: detectedLocation,
    );
    await createPost(post);
  }

  // デバッグ用：すべての投稿を取得
  static Future<List<PostModel>> getAllPosts() async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('posts')
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('全投稿取得エラー: $e');
      return [];
    }
  }
}