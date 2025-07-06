import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../screens/thread_screen.dart';
import '../services/countdown_like_service.dart';
import '../services/view_tracking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EnhancedCountdownCard extends StatefulWidget {
  final Countdown countdown;

  const EnhancedCountdownCard({super.key, required this.countdown});

  @override
  State<EnhancedCountdownCard> createState() => _EnhancedCountdownCardState();
}

class _EnhancedCountdownCardState extends State<EnhancedCountdownCard> {
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLikeStatus();
    _trackView();
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

  Future<void> _trackView() async {
    // 閲覧をトラッキング
    await ViewTrackingService.trackView(widget.countdown.id);
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
      
      // ハプティックフィードバック
      if (newLikeStatus) {
        // Flutter標準のハプティック
      }
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

  Color _getCategoryColor() {
    switch (widget.countdown.category) {
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

  Widget _buildTrendingIndicator() {
    // 最近の活動が多い場合のトレンド表示
    final recentActivity = widget.countdown.recentCommentsCount + 
                          widget.countdown.recentLikesCount + 
                          widget.countdown.recentViewsCount;
    
    if (recentActivity >= 10) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.trending_up, size: 12, color: Colors.white),
            const SizedBox(width: 2),
            Text(
              'HOT',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ThreadScreen(countdown: widget.countdown),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー部分
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(),
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
                  const SizedBox(width: 8),
                  _buildTrendingIndicator(),
                  const Spacer(),
                  // 閲覧数表示
                  Row(
                    children: [
                      Icon(Icons.visibility, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.countdown.viewsCount}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // イベント名
              Text(
                widget.countdown.eventName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // イベント日時
              Text(
                'イベント日時: ${widget.countdown.eventDate.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),

              // カウントダウン表示
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: _getCategoryColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTimeRemaining(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getCategoryColor(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 統計情報とアクション
              Row(
                children: [
                  // 参加者数
                  Row(
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.countdown.participantsCount}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // コメント数
                  Row(
                    children: [
                      Icon(Icons.comment_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.countdown.commentsCount}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // いいねボタン
                  GestureDetector(
                    onTap: _toggleLike,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isLiked ? Colors.red[50] : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isLiked ? Colors.red : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _isLiked ? Colors.red : Colors.grey,
                                    ),
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    _isLiked ? Icons.favorite : Icons.favorite_border,
                                    key: ValueKey(_isLiked),
                                    size: 16,
                                    color: _isLiked ? Colors.red : Colors.grey[600],
                                  ),
                                ),
                          const SizedBox(width: 4),
                          Text(
                            '$_likesCount',
                            style: TextStyle(
                              color: _isLiked ? Colors.red : Colors.grey[600],
                              fontSize: 14,
                              fontWeight: _isLiked ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}