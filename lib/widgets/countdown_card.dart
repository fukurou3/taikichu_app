import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../screens/thread_screen.dart';
import '../services/comment_service.dart';
import '../services/countdown_like_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CountdownCard extends StatefulWidget {
  final Countdown countdown;

  const CountdownCard({super.key, required this.countdown});

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard> {
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLikeStatus();
  }

  Future<void> _loadLikeStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final isLiked = await CountdownLikeService.isLiked(widget.countdown.id, user.uid);
      setState(() {
        _isLiked = isLiked;
        _likesCount = widget.countdown.likesCount;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final newLikeStatus = await CountdownLikeService.toggleLike(widget.countdown.id);
      setState(() {
        _isLiked = newLikeStatus;
        _likesCount = newLikeStatus ? _likesCount + 1 : _likesCount - 1;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatTimeRemaining() {
    final now = DateTime.now();
    final difference = widget.countdown.eventDate.difference(now);
    
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

  Color _getUnifiedColor() {
    return const Color(0xFF1DA1F2); // Twitterブルーで統一
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ThreadScreen(countdown: widget.countdown),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
            ),
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getUnifiedColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.countdown.category,
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
                      '${widget.countdown.participantsCount}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.countdown.commentsCount}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: _isLiked ? Colors.red : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_likesCount',
                            style: TextStyle(
                              color: _isLiked ? Colors.red : Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.countdown.eventName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.countdown.eventDate.year}年${widget.countdown.eventDate.month}月${widget.countdown.eventDate.day}日',
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