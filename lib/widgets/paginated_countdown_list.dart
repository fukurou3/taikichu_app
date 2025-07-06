import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';
import '../services/paginated_service.dart';
import 'countdown_card.dart';

class PaginatedCountdownList extends StatefulWidget {
  final String? category;
  final String orderBy;
  final bool descending;

  const PaginatedCountdownList({
    super.key,
    this.category,
    this.orderBy = 'eventDate',
    this.descending = false,
  });

  @override
  State<PaginatedCountdownList> createState() => _PaginatedCountdownListState();
}

class _PaginatedCountdownListState extends State<PaginatedCountdownList> {
  final List<Countdown> _countdowns = [];
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
      final result = await PaginatedService.getCountdownsPaginated(
        category: widget.category,
        orderBy: widget.orderBy,
        descending: widget.descending,
        limit: 10,
      );

      _countdowns.clear();
      for (final item in result.items) {
        _countdowns.add(_mapToCountdown(item));
      }

      _lastDocument = result.lastDocument;
      _hasMore = result.hasMore;
    } catch (e) {
      print('Error loading initial data: $e');
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
      final result = await PaginatedService.getCountdownsPaginated(
        category: widget.category,
        orderBy: widget.orderBy,
        descending: widget.descending,
        startAfter: _lastDocument,
        limit: 10,
      );

      for (final item in result.items) {
        _countdowns.add(_mapToCountdown(item));
      }

      _lastDocument = result.lastDocument;
      _hasMore = result.hasMore;
    } catch (e) {
      print('Error loading more data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Countdown _mapToCountdown(Map<String, dynamic> data) {
    return Countdown(
      id: data['id'] as String,
      eventName: data['eventName'] as String,
      eventDate: (data['eventDate'] as Timestamp).toDate(),
      category: data['category'] as String,
      imageUrl: data['imageUrl'] as String?,
      creatorId: data['creatorId'] as String,
      participantsCount: data['participantsCount'] as int? ?? 0,
      likesCount: data['likesCount'] as int? ?? 0,
      commentsCount: data['commentsCount'] as int? ?? 0,
    );
  }

  Future<void> _onRefresh() async {
    _lastDocument = null;
    _hasMore = true;
    await _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_countdowns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'まだカウントダウンがありません',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '右下のボタンから作成しましょう！',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _countdowns.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _countdowns.length) {
            // ローディングインジケーター
            return Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            );
          }

          return CountdownCard(countdown: _countdowns[index]);
        },
      ),
    );
  }
}