import 'package:flutter/material.dart';
import '../models/countdown.dart';
import '../services/countdown_search_service.dart';
import '../services/trend_ranking_service.dart';
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
  List<Countdown> _categoryResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _showingCategory = false;
  String? _currentCategory;
  
  // 大カテゴリ（運営が設定したカテゴリ）
  final List<Map<String, dynamic>> _bigCategories = [
    {
      'name': 'ゲーム',
      'icon': Icons.sports_esports,
      'color': Colors.blue,
      'description': 'ゲームリリース、アップデート、イベント'
    },
    {
      'name': '音楽',
      'icon': Icons.music_note,
      'color': Colors.purple,
      'description': 'ライブ、新曲リリース、コンサート'
    },
    {
      'name': 'アニメ',
      'icon': Icons.movie,
      'color': Colors.orange,
      'description': 'アニメ放送、映画公開、イベント'
    },
    {
      'name': 'ライブ',
      'icon': Icons.celebration,
      'color': Colors.red,
      'description': 'コンサート、フェス、ライブイベント'
    },
    {
      'name': '推し活',
      'icon': Icons.favorite,
      'color': Colors.pink,
      'description': '誕生日、記念日、ファンイベント'
    },
    {
      'name': 'その他',
      'icon': Icons.more_horiz,
      'color': Colors.grey,
      'description': 'その他のイベント・記念日'
    },
  ];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearchText ?? '';
    
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

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
        _showingCategory = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _showingCategory = false;
    });

    try {
      final results = await CountdownSearchService.searchSimilarCountdowns(
        eventName: _searchController.text.trim(),
        eventDate: widget.initialEventDate,
      );

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('検索エラー: $e')),
        );
      }
    }
  }

  Future<void> _loadCategoryCountdowns(String category) async {
    setState(() {
      _isLoading = true;
      _showingCategory = true;
      _currentCategory = category;
      _hasSearched = false;
    });

    try {
      final results = await TrendRankingService.getCountdownsByCategory(
        category: category,
        limit: 20,
      );

      setState(() {
        _categoryResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('カテゴリ読み込みエラー: $e')),
        );
      }
    }
  }

  void _onCategoryTap(String category) {
    // カテゴリのカウントダウン一覧を表示
    _loadCategoryCountdowns(category);
  }

  void _onCreateInCategory() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCountdownScreen(
          preFilledCategory: _currentCategory,
          preFilledEventDate: widget.initialEventDate,
        ),
      ),
    );
  }

  void _proceedToCreate() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCountdownScreen(
          preFilledEventName: _searchController.text.trim(),
          preFilledEventDate: widget.initialEventDate,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'イベントを検索',
          hintStyle: TextStyle(
            color: Colors.grey[500],
            fontSize: 16,
          ),
          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _hasSearched = false;
                      _searchResults = [];
                      _showingCategory = false;
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: const TextStyle(fontSize: 16),
        onChanged: (value) {
          setState(() {});
          if (value.trim().length >= 2) {
            _performSearch();
          } else if (value.trim().isEmpty) {
            setState(() {
              _hasSearched = false;
              _searchResults = [];
              _showingCategory = false;
            });
          }
        },
        onSubmitted: (value) => _performSearch(),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'カテゴリから選ぶ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.8,
            ),
            itemCount: _bigCategories.length,
            itemBuilder: (context, index) {
              final category = _bigCategories[index];
              return _buildCategoryCard(category);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    return GestureDetector(
      onTap: () => _onCategoryTap(category['name']),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: category['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    category['icon'],
                    color: category['color'],
                    size: 20,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              category['name'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category['description'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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

    // カテゴリ表示モード
    if (_showingCategory) {
      return _buildCategoryResults();
    }

    // 検索結果表示モード
    if (_searchResults.isEmpty && _hasSearched) {
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
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isNotEmpty) {
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // デフォルト状態：カテゴリグリッドを表示
    return SingleChildScrollView(
      child: _buildCategoryGrid(),
    );
  }

  Widget _buildCategoryResults() {
    final categoryInfo = _bigCategories.firstWhere(
      (cat) => cat['name'] == _currentCategory,
      orElse: () => {'name': _currentCategory, 'color': Colors.grey},
    );

    return Column(
      children: [
        // カテゴリヘッダー
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: categoryInfo['color'].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  categoryInfo['icon'] ?? Icons.category,
                  color: categoryInfo['color'],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentCategory ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'トレンド順に表示',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _onCreateInCategory,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('作成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: categoryInfo['color'],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        // カテゴリ内のカウントダウン一覧
        Expanded(
          child: _categoryResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'まだ${_currentCategory}のカウントダウンがありません',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '最初のカウントダウンを作成してみませんか？',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _onCreateInCategory,
                          icon: const Icon(Icons.add),
                          label: const Text('最初のカウントダウンを作成'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: categoryInfo['color'],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _categoryResults.length,
                  itemBuilder: (context, index) {
                    return EnhancedCountdownCard(countdown: _categoryResults[index]);
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildSearchResults()),
          ],
        ),
      ),
    );
  }
}