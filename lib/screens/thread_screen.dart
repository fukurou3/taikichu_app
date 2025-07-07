import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/countdown.dart';
import '../models/comment.dart';
import '../services/unified_analytics_service.dart';
import '../services/scalable_participant_service.dart';
import '../widgets/paginated_comment_list.dart';
import 'hashtag_search_screen.dart';

class ThreadScreen extends StatefulWidget {
  final Countdown countdown;

  const ThreadScreen({super.key, required this.countdown});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  bool _isParticipating = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _trackView();
    _loadParticipationStatus();
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
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 🚀 統一パイプライン対応: スケーラブル参加サービス使用
      final newStatus = await ScalableParticipantService.toggleParticipation(widget.countdown.id);
      setState(() {
        _isParticipating = newStatus;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? '参加しました！' : '参加を取り消しました'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _trackView() async {
    try {
      // 🚀 統一パイプライン: 閲覧イベント送信
      await UnifiedAnalyticsService.sendViewEvent(widget.countdown.id);
    } catch (e) {
      print('Error tracking view: $e');
    }
  }


  Color _getUnifiedColor() {
    return const Color(0xFF1DA1F2); // Twitterブルーで統一
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

  String _formatEventDate() {
    final date = widget.countdown.eventDate;
    return '${date.year}年${date.month}月${date.day}日 ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDescriptionWithHashtags() {
    final description = widget.countdown.description;
    print('ThreadScreen - Countdown ${widget.countdown.id}: Description: "$description"'); // デバッグ用
    print('ThreadScreen - Countdown ${widget.countdown.id}: Description type: ${description.runtimeType}'); // デバッグ用
    
    if (description == null || description.isEmpty) {
      print('ThreadScreen - Description is null or empty'); // デバッグ用
      return const SizedBox.shrink(); // 説明文がない場合は何も表示しない
    }
    
    final spans = <TextSpan>[];
    int lastIndex = 0;
    final regex = RegExp(r'#[^\s#]+');
    final matches = regex.allMatches(description);
    
    for (final match in matches) {
      // ハッシュタグ前のテキスト
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: description.substring(lastIndex, match.start),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
          ),
        ));
      }
      
      // ハッシュタグ（タップ可能）
      final hashtag = match.group(0)!.substring(1); // # を除去
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          color: Color(0xFF1DA1F2),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HashtagSearchScreen(hashtag: hashtag),
              ),
            );
          },
      ));
      
      lastIndex = match.end;
    }
    
    // 残りのテキスト
    if (lastIndex < description.length) {
      spans.add(TextSpan(
        text: description.substring(lastIndex),
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
        ),
      ));
    }
    
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RichText(
        text: TextSpan(children: spans),
      ),
    );
  }

  Widget _buildMainTweet() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザー情報
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[200],
                child: const Icon(
                  Icons.person,
                  color: Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '匿名ユーザー',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '@anonymous',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // カテゴリ表示
              Text(
                widget.countdown.category,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // イベント名
          Text(
            widget.countdown.eventName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          
          // 説明文とハッシュタグ
          _buildDescriptionWithHashtags(),
          
          const SizedBox(height: 16),
          
          // カウントダウン表示
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.schedule,
                  color: _getUnifiedColor(),
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTimeRemaining(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getUnifiedColor(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatEventDate(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Twitter風統計情報（アイコンと数字のみ）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatIcon(Icons.chat_bubble_outline, '${widget.countdown.commentsCount}'),
              GestureDetector(
                onTap: _toggleParticipation,
                child: _buildParticipantIcon(),
              ),
              _buildStatIcon(Icons.favorite_border, '${widget.countdown.likesCount}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatIcon(IconData icon, String count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildParticipantIcon() {
    if (_isLoading) {
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'カウントダウン',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: Colors.grey[600]),
            onPressed: () {
              // メニューオプション
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // メインツイート
          _buildMainTweet(),
          
          // コメント一覧（コメント投稿欄は削除）
          Expanded(
            child: PaginatedCommentList(
              countdownId: widget.countdown.id,
              onLike: (comment) {
                // いいね機能のプレースホルダー
              },
              onReply: (comment) {
                // 返信機能のプレースホルダー
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

