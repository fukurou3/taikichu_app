import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import '../models/comment.dart';
import '../services/comment_service.dart';
import '../widgets/comment_card.dart';

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
  }

  void _onCommentChanged() {
    setState(() {
      _isCommentEmpty = _commentController.text.trim().isEmpty;
    });
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

  String _formatCommentTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays > 0) {
      return "${difference.inDays}日前";
    } else if (difference.inHours > 0) {
      return "${difference.inHours}時間前";
    } else if (difference.inMinutes > 0) {
      return "${difference.inMinutes}分前";
    } else {
      return "たった今";
    }
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
      
      // 新しいコメントが見えるように下にスクロール
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

  void _handleLike(Comment comment) {
    // いいね機能のプレースホルダー
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('いいね機能は今後実装予定です')),
    );
  }

  void _handleReply(Comment comment) {
    // 返信機能のプレースホルダー
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('返信機能は今後実装予定です')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.countdown.eventName),
        backgroundColor: _getCategoryColor(),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // カウントダウン情報
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
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
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.countdown.eventName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.countdown.eventDate.year}年${widget.countdown.eventDate.month}月${widget.countdown.eventDate.day}日',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
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
              ],
            ),
          ),
          
          // コメント一覧
          Expanded(
            child: StreamBuilder<List<Comment>>(
              stream: CommentService.getCommentsStream(widget.countdown.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('エラーが発生しました: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final comments = snapshot.data ?? [];

                if (comments.isEmpty) {
                  return const Center(
                    child: Text(
                      'まだコメントがありません。\n最初のコメントを投稿しましょう！',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return CommentCard(
                      comment: comment,
                      onLike: () => _handleLike(comment),
                      onReply: () => _handleReply(comment),
                    );
                  },
                );
              },
            ),
          ),
          
          // コメント入力フォーム
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey, width: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // アバター
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  child: const Text(
                    'あ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // 入力フィールド
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'ツイートを入力',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: Colors.grey,
                        fontSize: 18,
                      ),
                    ),
                    style: const TextStyle(fontSize: 18),
                    maxLines: null,
                    onSubmitted: (_) => _postComment(),
                  ),
                ),
                
                // 投稿ボタン
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: ElevatedButton(
                    onPressed: _isCommentEmpty ? null : _postComment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getCategoryColor(),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 0,
                    ),
                    child: const Text(
                      'ツイート',
                      style: TextStyle(
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