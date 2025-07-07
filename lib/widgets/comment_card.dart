import 'package:flutter/material.dart';
import '../models/comment.dart';
import 'report_dialog.dart';

class CommentCard extends StatelessWidget {
  final Comment comment;
  final VoidCallback? onLike;
  final VoidCallback? onReply;

  const CommentCard({
    super.key,
    required this.comment,
    this.onLike,
    this.onReply,
  });

  String _formatCommentTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays > 0) {
      return "${difference.inDays}日";
    } else if (difference.inHours > 0) {
      return "${difference.inHours}時間";
    } else if (difference.inMinutes > 0) {
      return "${difference.inMinutes}分";
    } else {
      return "今";
    }
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return "${(count / 1000).toStringAsFixed(1)}K";
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アバター
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[300],
            child: Text(
              comment.authorName[0].toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // コンテンツ部分
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー（名前・時間）
                Row(
                  children: [
                    Text(
                      comment.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '・${_formatCommentTime(comment.createdAt)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                
                // コメント内容
                Text(
                  comment.content,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                
                // アクションボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 返信ボタン
                    _ActionButton(
                      icon: Icons.chat_bubble_outline,
                      count: comment.repliesCount,
                      onTap: onReply,
                      color: Colors.grey[600]!,
                    ),
                    
                    // いいねボタン
                    _ActionButton(
                      icon: Icons.favorite_border,
                      count: comment.likesCount,
                      onTap: onLike,
                      color: Colors.grey[600]!,
                    ),
                    
                    // シェアボタン（見た目のみ）
                    _ActionButton(
                      icon: Icons.share_outlined,
                      count: 0,
                      onTap: () {},
                      color: Colors.grey[600]!,
                      showCount: false,
                    ),
                    
                    // その他ボタン
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.grey[600],
                        size: 18,
                      ),
                      onSelected: (value) {
                        if (value == 'report') {
                          showReportDialog(
                            context: context,
                            contentId: comment.id,
                            contentType: 'comment',
                            contentTitle: comment.content.length > 30 
                                ? '${comment.content.substring(0, 30)}...'
                                : comment.content,
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('通報する'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  final Color color;
  final bool showCount;

  const _ActionButton({
    required this.icon,
    required this.count,
    this.onTap,
    required this.color,
    this.showCount = true,
  });

  String _formatCount(int count) {
    if (count >= 1000) {
      return "${(count / 1000).toStringAsFixed(1)}K";
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: color,
            ),
            if (showCount && count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _formatCount(count),
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}