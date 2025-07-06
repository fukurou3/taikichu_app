import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../services/countdown_search_service.dart';
import '../widgets/enhanced_countdown_card.dart';
import 'create_countdown_screen.dart';

class CountdownSearchScreen extends StatefulWidget {
  final String? initialSearchText;
  final String? initialCategory;
  final DateTime? initialEventDate;

  const CountdownSearchScreen({
    super.key,
    this.initialSearchText,
    this.initialCategory,
    this.initialEventDate,
  });

  @override
  State<CountdownSearchScreen> createState() => _CountdownSearchScreenState();
}

class _CountdownSearchScreenState extends State<CountdownSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<Countdown> _searchResults = [];
  List<String> _popularCategories = [];
  String? _selectedCategory;
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearchText ?? '';
    _selectedCategory = widget.initialCategory;
    _loadPopularCategories();
    
    if (widget.initialSearchText?.isNotEmpty == true) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPopularCategories() async {
    final categories = await CountdownSearchService.getPopularCategories();
    setState(() {
      _popularCategories = categories;
    });
  }

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await CountdownSearchService.searchSimilarCountdowns(
        eventName: _searchController.text.trim(),
        category: _selectedCategory,
        eventDate: widget.initialEventDate,
      );

      setState(() {
        _searchResults = results;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasSearched = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('検索エラー: $e')),
      );
    }
  }

  void _proceedToCreate() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCountdownScreen(
          preFilledEventName: _searchController.text.trim(),
          preFilledCategory: _selectedCategory,
          preFilledEventDate: widget.initialEventDate,
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '類似のカウントダウンを検索',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '作成前に、同じようなイベントがないか確認しましょう',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          
          // 検索フィールド
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'イベント名を入力してください',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _performSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: (value) {
              setState(() {});
              if (value.trim().length >= 2) {
                _performSearch();
              }
            },
            onSubmitted: (value) => _performSearch(),
          ),
          const SizedBox(height: 12),
          
          // カテゴリフィルター
          if (_popularCategories.isNotEmpty) ...[
            const Text(
              'カテゴリで絞り込み',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('すべて'),
                  selected: _selectedCategory == null,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = null;
                    });
                    if (_hasSearched) _performSearch();
                  },
                ),
                ..._popularCategories.map((category) {
                  return FilterChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = selected ? category : null;
                      });
                      if (_hasSearched) _performSearch();
                    },
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_hasSearched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.search,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'イベント名を入力して検索してください',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              const Text(
                '類似のカウントダウンは見つかりませんでした',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '新しいカウントダウンを作成できます！',
                style: TextStyle(
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _proceedToCreate,
                icon: const Icon(Icons.add),
                label: const Text('カウントダウンを作成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.orange[50],
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '類似のカウントダウンが見つかりました',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                    const Text(
                      '既存のものに参加するか、新しく作成するか選択してください',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              return EnhancedCountdownCard(countdown: _searchResults[index]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _proceedToCreate,
              icon: const Icon(Icons.add),
              label: const Text('それでも新しく作成する'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('カウントダウン検索'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(child: _buildSearchResults()),
        ],
      ),
    );
  }
}