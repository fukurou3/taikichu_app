import 'package:cloud_firestore/cloud_firestore.dart';

class Countdown {
  final String id;
  final String eventName;
  final DateTime eventDate;
  final String category;
  final String? imageUrl;
  final String creatorId;
  final int participantsCount;

  Countdown({
    required this.id,
    required this.eventName,
    required this.eventDate,
    required this.category,
    this.imageUrl,
    required this.creatorId,
    this.participantsCount = 0,
  });

  factory Countdown.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return Countdown(
      id: snapshot.id,
      eventName: data?['eventName'] as String,
      eventDate: (data?['eventDate'] as Timestamp).toDate(),
      category: data?['category'] as String,
      imageUrl: data?['imageUrl'] as String?,
      creatorId: data?['creatorId'] as String,
      participantsCount: data?['participantsCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "eventName": eventName,
      "eventDate": Timestamp.fromDate(eventDate),
      "category": category,
      if (imageUrl != null) "imageUrl": imageUrl,
      "creatorId": creatorId,
      "participantsCount": participantsCount,
    };
  }
}