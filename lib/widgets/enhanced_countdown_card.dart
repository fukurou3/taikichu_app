import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../screens/thread_screen.dart';
import '../services/scalable_like_service.dart';
import '../services/unified_analytics_service.dart';
import '../services/scalable_participant_service.dart';
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
  bool _isParticipating = false;
  bool _isParticipantLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLikeStatus();
    _loadParticipationStatus();
    _trackView();
  }

  Future<void> _loadParticipationStatus() async {
    try {
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final isParticipating = await ScalableParticipantService.isParticipating(widget.countdown.id);
      setState(() {
        _isParticipating = isParticipating;
      });
    } catch (e) {
      print('Error loading participation status: $e');
    }
  }

  Future<void> _toggleParticipation() async {
    if (_isParticipantLoading) return;
    
    setState(() {
      _isParticipantLoading = true;
    });

    try {
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final newStatus = await ScalableParticipantService.toggleParticipation(widget.countdown.id);
      setState(() {
        _isParticipating = newStatus;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    } finally {
      setState(() {
        _isParticipantLoading = false;
      });
    }
  }

  Future<void> _loadLikeStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 🚀 統一パイプライン対応: スケーラブルいいねサービス使用
      final isLiked = await ScalableLikeService.isLiked(widget.countdown.id, user.uid);
      final likesCount = await ScalableLikeService.getLikesCount(widget.countdown.id);
      setState(() {
        _isLiked = isLiked;
        _likesCount = likesCount;
      });
    }
  }

  Future<void> _trackView() async {
    // 🚀 統一パイプライン: 閲覧イベント送信
    await UnifiedAnalyticsService.sendViewEvent(widget.countdown.id);
  }

  Future<void> _toggleLike() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 🚀 統一パイプライン対応: スケーラブルいいねサービス使用
      final newLikeStatus = await ScalableLikeService.toggleLike(widget.countdown.id);
      
      // 最新のいいね数を取得（Redis高速アクセス）
      final latestCount = await ScalableLikeService.getLikesCount(widget.countdown.id);
      
      setState(() {
        _isLiked = newLikeStatus;
        _likesCount = latestCount;
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

  Color _getUnifiedColor() {
    return const Color(0xFF1DA1F2); // Twitterブルーで統一
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

  Widget _buildActionButton(IconData icon, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildParticipantButton() {
    if (_isParticipantLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                _isParticipating ? const Color(0xFF1DA1F2) : Colors.grey[600]!,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${widget.countdown.participantsCount}',
            style: TextStyle(
              color: _isParticipating ? const Color(0xFF1DA1F2) : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _isParticipating ? Icons.people : Icons.people_outline,
          size: 18,
          color: _isParticipating ? const Color(0xFF1DA1F2) : Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Text(
          '${widget.countdown.participantsCount}',
          style: TextStyle(
            color: _isParticipating ? const Color(0xFF1DA1F2) : Colors.grey[600],
            fontSize: 14,
            fontWeight: _isParticipating ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionWithHashtags() {
    final description = widget.countdown.description;
    if (description == null || description.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final hashtags = widget.countdown.hashtags;
    print('EnhancedCountdownCard - Widget ${widget.countdown.id}: Description: "$description"'); // デバッグ用
    print('EnhancedCountdownCard - Widget ${widget.countdown.id}: Hashtags: $hashtags'); // デバッグ用
    print('EnhancedCountdownCard - Widget ${widget.countdown.id}: Description isEmpty: ${description.isEmpty}'); // デバッグ用
    print('EnhancedCountdownCard - Widget ${widget.countdown.id}: Hashtags count: ${hashtags.length}'); // デバッグ用
    
    // ハッシュタグをハイライト表示するためのSpanを作成
    final spans = <TextSpan>[];
    
    // ハッシュタグの位置を検索
    int lastIndex = 0;
    final regex = RegExp(r'#[^\s#]+');
    final matches = regex.allMatches(description);
    
    for (final match in matches) {
      // ハッシュタグ前のテキスト
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: description.substring(lastIndex, match.start),
          style: const TextStyle(color: Colors.black87),
        ));
      }
      
      // ハッシュタグ
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          color: Color(0xFF1DA1F2),
          fontWeight: FontWeight.w500,
        ),
      ));
      
      lastIndex = match.end;
    }
    
    // 残りのテキスト
    if (lastIndex < description.length) {
      spans.add(TextSpan(
        text: description.substring(lastIndex),
        style: const TextStyle(color: Colors.black87),
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
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
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー部分 - Twitter風
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[200],
                    child: const Icon(
                      Icons.event,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.countdown.category,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildTrendingIndicator(),
                          ],
                        ),
                        Text(
                          '@countdown',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
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

              // 説明文とハッシュタグ
              _buildDescriptionWithHashtags(),
              const SizedBox(height: 8),

              // イベント日時
              Text(
                'イベント日時: ${widget.countdown.eventDate.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),

              // カウントダウン表示
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      color: Color(0xFF1DA1F2),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeRemaining(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                  ],
                ),
              ),

              // Twitter風アクションボタン
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // コメント
                  _buildActionButton(
                    Icons.chat_bubble_outline,
                    '${widget.countdown.commentsCount}',
                    Colors.grey[600]!,
                  ),
                  // 参加者（タップ可能）
                  GestureDetector(
                    onTap: _toggleParticipation,
                    child: _buildParticipantButton(),
                  ),
                  // いいね
                  GestureDetector(
                    onTap: _toggleLike,
                    child: _buildActionButton(
                      _isLiked ? Icons.favorite : Icons.favorite_border,
                      '$_likesCount',
                      _isLiked ? Colors.red : Colors.grey[600]!,
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