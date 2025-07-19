enum PostType { casual, serious }
enum LocationType { municipality, coordinates }

class LatLng {
  final double latitude;
  final double longitude;
  
  const LatLng(this.latitude, this.longitude);
  
  @override
  String toString() => 'LatLng($latitude, $longitude)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

class PostModel {
  final String id;
  final PostType type;
  final String content;
  final String? title; // 真剣投稿のみ
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final LocationType? locationType;
  final String? municipality;
  final double? latitude;
  final double? longitude;
  final String? detectedLocation;

  const PostModel({
    required this.id,
    required this.type,
    required this.content,
    this.title,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.locationType,
    this.municipality,
    this.latitude,
    this.longitude,
    this.detectedLocation,
  });

  factory PostModel.fromFirestore(String id, Map<String, dynamic> data) {
    return PostModel(
      id: id,
      type: data['type'] == 'casual' ? PostType.casual : PostType.serious,
      content: data['content'] ?? '',
      title: data['title'],
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      locationType: data['locationType'] != null 
          ? (data['locationType'].toString().contains('municipality') 
              ? LocationType.municipality 
              : LocationType.coordinates)
          : null,
      municipality: data['municipality'],
      latitude: data['latitude']?.toDouble(),
      longitude: data['longitude']?.toDouble(),
      detectedLocation: data['detectedLocation'],
    );
  }

  Map<String, dynamic> toFirestore() {
    final Map<String, dynamic> data = {
      'type': type == PostType.casual ? 'casual' : 'serious',
      'content': content,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': createdAt,
    };

    if (title != null) data['title'] = title;
    if (locationType != null) {
      data['locationType'] = locationType.toString();
    }
    if (municipality != null) data['municipality'] = municipality;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (detectedLocation != null) data['detectedLocation'] = detectedLocation;

    return data;
  }

  bool get hasLocation => municipality != null || (latitude != null && longitude != null);
  
  LatLng? get coordinates => 
      latitude != null && longitude != null ? LatLng(latitude!, longitude!) : null;
}