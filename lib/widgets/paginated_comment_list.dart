import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';
import '../services/paginated_service.dart';
import 'comment_card.dart';

class PaginatedCommentList extends StatefulWidget {
  final String countdownId;
  final Function(Comment)? onLike;
  final Function(Comment)? onReply;

  const PaginatedCommentList({
    super.key,
    required this.countdownId,
    this.onLike,
    this.onReply,
  });

  @override
  State<PaginatedCommentList> createState() => _PaginatedCommentListState();
}

class _PaginatedCommentListState extends State<PaginatedCommentList> {
  final List<Comment> _comments = [];
  final ScrollController _scrollController = ScrollController();
  
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreData();
    }
  }

  Future<void> _loadInitialData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _isInitialized = false;
    });

    try {
      final result = await PaginatedService.getCommentsPaginated(
        countdownId: widget.countdownId,
        limit: 20,
      );

      _comments.clear();
      for (final item in result.items) {
        _comments.add(_mapToComment(item));
      }

      _lastDocument = result.lastDocument;
      _hasMore = result.hasMore;
    } catch (e) {
      print('Error loading initial comments: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isInitialized = true;
      });
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await PaginatedService.getCommentsPaginated(
        countdownId: widget.countdownId,
        startAfter: _lastDocument,
        limit: 20,
      );

      for (final item in result.items) {
        _comments.add(_mapToComment(item));
      }

      _lastDocument = result.lastDocument;
      _hasMore = result.hasMore;
    } catch (e) {
      print('Error loading more comments: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Comment _mapToComment(Map<String, dynamic> data) {
    return Comment(
      id: data['id'] as String,
      countdownId: data['countdownId'] as String,
      content: data['content'] as String,
      authorId: data['authorId'] as String,
      authorName: data['authorName'] as String? ?? 'ユーザー',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      likesCount: data['likesCount'] as int? ?? 0,
      repliesCount: data['repliesCount'] as int? ?? 0,
    );
  }

  Future<void> _onRefresh() async {
    _lastDocument = null;
    _hasMore = true;
    await _loadInitialData();
  }

  void _addNewComment(Comment comment) {
    setState(() {
      _comments.insert(0, comment);
    });
    
    // 新しいコメントが見えるようにスクロール
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'まだコメントがありません',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '最初のコメントを投稿しましょう！',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _comments.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _comments.length) {
            // ローディングインジケーター
            return Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            );
          }

          final comment = _comments[index];
          return CommentCard(
            comment: comment,
            onLike: widget.onLike != null ? () => widget.onLike!(comment) : null,
            onReply: widget.onReply != null ? () => widget.onReply!(comment) : null,
          );
        },
      ),
    );
  }
}