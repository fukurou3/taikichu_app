import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';

class CountdownService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'counts';

  static Stream<List<Countdown>> getCountdownsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('eventDate', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Countdown.fromFirestore(doc, null);
      }).toList();
    });
  }

  static Future<void> addCountdown(Countdown countdown) async {
    await _firestore.collection(_collection).add(countdown.toFirestore());
  }

  static Future<void> updateParticipantsCount(String countdownId, int newCount) async {
    await _firestore
        .collection(_collection)
        .doc(countdownId)
        .update({'participantsCount': newCount});
  }

  static Future<void> updateLikesCount(String countdownId, int increment) async {
    await _firestore
        .collection(_collection)
        .doc(countdownId)
        .update({'likesCount': FieldValue.increment(increment)});
  }

  static Future<void> updateCommentsCount(String countdownId, int increment) async {
    await _firestore
        .collection(_collection)
        .doc(countdownId)
        .update({'commentsCount': FieldValue.increment(increment)});
  }

  static Future<void> deleteCountdown(String countdownId) async {
    await _firestore.collection(_collection).doc(countdownId).delete();
  }
}