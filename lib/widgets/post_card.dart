import 'package:flutter/material.dart';
import '../models/post_models.dart';
import '../utils/date_utils.dart' as app_date_utils;

class PostCard extends StatelessWidget {
  final PostModel post;

  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー部分
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: post.type == PostType.casual 
                      ? Colors.blue[100] 
                      : Colors.orange[100],
                  child: Icon(
                    post.type == PostType.casual ? Icons.chat_bubble : Icons.assignment,
                    color: post.type == PostType.casual ? Colors.blue : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        app_date_utils.DateUtils.formatDateTime(post.createdAt),
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

            // タイトル（真剣投稿のみ）
            if (post.title != null) ...[
              Text(
                post.title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 内容
            Text(
              post.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),

            // 位置情報
            if (post.hasLocation) _buildLocationInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInfo() {
    if (post.municipality != null) {
      return Row(
        children: [
          const Icon(Icons.location_city, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            post.municipality!,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      );
    } else if (post.coordinates != null) {
      return Column(
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
          if (post.detectedLocation != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '(${post.detectedLocation})',
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}