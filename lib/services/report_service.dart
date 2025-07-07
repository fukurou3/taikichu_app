import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ユーザーが投稿を通報する
  static Future<bool> reportContent({
    required String contentId,
    required String contentType, // 'countdown' または 'comment'
    required String reason,
    String? description,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ログインが必要です');
      }

      // 同じユーザーが同じコンテンツを重複して通報していないかチェック
      final existingReport = await _firestore
          .collection('reports')
          .where('contentId', isEqualTo: contentId)
          .where('reportedBy', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existingReport.docs.isNotEmpty) {
        throw Exception('このコンテンツは既に通報済みです');
      }

      // 通報データを作成
      final reportData = {
        'contentId': contentId,
        'contentType': contentType,
        'reportedBy': user.uid,
        'reason': reason,
        'description': description ?? '',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Firestoreに通報を保存
      await _firestore.collection('reports').add(reportData);

      return true;
    } catch (e) {
      print('Error reporting content: $e');
      return false;
    }
  }

  /// 通報理由の選択肢を取得
  static List<String> getReportReasons() {
    return [
      'スパム・宣伝',
      '不適切な内容',
      '嫌がらせ・誹謗中傷',
      '著作権侵害',
      '偽情報',
      'その他',
    ];
  }

  /// ユーザーが特定のコンテンツを通報済みかチェック
  static Future<bool> hasUserReported({
    required String contentId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final existingReport = await _firestore
          .collection('reports')
          .where('contentId', isEqualTo: contentId)
          .where('reportedBy', isEqualTo: user.uid)
          .limit(1)
          .get();

      return existingReport.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if user has reported: $e');
      return false;
    }
  }
}