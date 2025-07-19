import 'package:flutter/material.dart';
import '../models/post_models.dart';
import '../utils/date_utils.dart' as app_date_utils;

class PostCard extends StatefulWidget {
  final PostModel post;

  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.grey[50] : Colors.white,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFEFF3F4), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // アバター
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: widget.post.type == PostType.casual 
                        ? [Colors.blue[400]!, Colors.blue[600]!]
                        : [Colors.orange[400]!, Colors.orange[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  widget.post.type == PostType.casual ? Icons.chat_bubble_outline : Icons.assignment_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              
              // コンテンツ部分
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ヘッダー情報
                    Row(
                      children: [
                        Text(
                          widget.post.authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF0F1419),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '@${widget.post.authorName.toLowerCase().replaceAll(' ', '')}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '·',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          app_date_utils.DateUtils.formatDateTime(widget.post.createdAt),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // タイトル（真剣投稿のみ）
                    if (widget.post.title != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assignment, size: 14, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Text(
                              '真剣投稿',
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.post.title!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F1419),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 内容
                    Text(
                      widget.post.content,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF0F1419),
                        height: 1.3,
                      ),
                    ),

                    // 位置情報
                    if (widget.post.hasLocation) ...[
                      const SizedBox(height: 12),
                      _buildLocationInfo(),
                    ],

                    // アクションボタン
                    const SizedBox(height: 12),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfo() {
    if (widget.post.municipality != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[200]!, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_city, size: 14, color: Colors.blue[700]),
            const SizedBox(width: 4),
            Text(
              widget.post.municipality!,
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else if (widget.post.coordinates != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  '詳細位置',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (widget.post.detectedLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.post.detectedLocation!,
                  style: TextStyle(
                    color: Colors.green[600],
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        _buildActionButton(
          icon: Icons.chat_bubble_outline,
          count: 0,
          color: Colors.grey[600]!,
          onTap: () {},
        ),
        const SizedBox(width: 32),
        _buildActionButton(
          icon: Icons.repeat,
          count: 0,
          color: Colors.grey[600]!,
          onTap: () {},
        ),
        const SizedBox(width: 32),
        _buildActionButton(
          icon: Icons.favorite_border,
          count: 0,
          color: Colors.grey[600]!,
          onTap: () {},
        ),
        const SizedBox(width: 32),
        _buildActionButton(
          icon: Icons.share_outlined,
          count: 0,
          color: Colors.grey[600]!,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}