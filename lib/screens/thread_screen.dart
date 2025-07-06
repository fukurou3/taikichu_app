import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import '../models/comment.dart';
import '../services/comment_service.dart';
import '../services/optimized_stream_service.dart';
import '../services/view_tracking_service.dart';
import '../widgets/comment_card.dart';
import '../widgets/paginated_comment_list.dart';
import 'hashtag_search_screen.dart';

class ThreadScreen extends StatefulWidget {
  final Countdown countdown;

  const ThreadScreen({super.key, required this.countdown});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isCommentEmpty = true;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_onCommentChanged);
    _trackView();
  }

  Future<void> _trackView() async {
    try {
      await ViewTrackingService.trackView(widget.countdown.id);
    } catch (e) {
      print('Error tracking view: $e');
    }
  }

  void _onCommentChanged() {
    setState(() {
      _isCommentEmpty = _commentController.text.trim().isEmpty;
    });
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
    
    if (description == null || description.isEmpty) {
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
          
          // 統計情報
          Row(
            children: [
              _buildStatItem(Icons.people, '${widget.countdown.participantsCount}', '参加者'),
              const SizedBox(width: 24),
              _buildStatItem(Icons.favorite, '${widget.countdown.likesCount}', 'いいね'),
              const SizedBox(width: 24),
              _buildStatItem(Icons.comment, '${widget.countdown.commentsCount}', 'コメント'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String count, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          count,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コメントを投稿するにはログインが必要です。')),
      );
      return;
    }

    try {
      final comment = Comment(
        id: '',
        countdownId: widget.countdown.id,
        content: _commentController.text.trim(),
        authorId: user.uid,
        authorName: '匿名ユーザー',
        createdAt: DateTime.now(),
      );

      await CommentService.addComment(comment);
      _commentController.clear();
      
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('コメント投稿に失敗しました: $e')),
      );
    }
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
          
          // コメント一覧
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
          
          // コメント入力フォーム
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'コメントを投稿',
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 16),
                    maxLines: null,
                    onSubmitted: (_) => _postComment(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isCommentEmpty ? null : _postComment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isCommentEmpty ? Colors.grey[300] : _getUnifiedColor(),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '投稿',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

