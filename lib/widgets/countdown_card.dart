import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../screens/thread_screen.dart';
import '../services/comment_service.dart';

class CountdownCard extends StatelessWidget {
  final Countdown countdown;

  const CountdownCard({super.key, required this.countdown});

  String _formatTimeRemaining() {
    final now = DateTime.now();
    final difference = countdown.eventDate.difference(now);
    
    if (difference.isNegative) {
      return "イベント終了";
    }
    
    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    
    if (days > 0) {
      return "あと${days}日 ${hours}時間";
    } else if (hours > 0) {
      return "あと${hours}時間 ${minutes}分";
    } else if (minutes > 0) {
      return "あと${minutes}分";
    } else {
      return "まもなく開始！";
    }
  }

  Color _getCategoryColor() {
    switch (countdown.category) {
      case 'ゲーム':
        return Colors.blue;
      case '音楽':
        return Colors.purple;
      case 'アニメ':
        return Colors.orange;
      case 'ライブ':
        return Colors.red;
      case '推し活':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ThreadScreen(countdown: countdown),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    countdown.category,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.people, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${countdown.participantsCount}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    FutureBuilder<int>(
                      future: CommentService.getCommentCount(countdown.id),
                      builder: (context, snapshot) {
                        return Text(
                          '${snapshot.data ?? 0}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              countdown.eventName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${countdown.eventDate.year}年${countdown.eventDate.month}月${countdown.eventDate.day}日',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTimeRemaining(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}