import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import '../services/countdown_service.dart';
import '../services/unified_analytics_service.dart';

class CreateCountdownScreen extends StatefulWidget {
  final String? preFilledEventName;
  final String? preFilledCategory;
  final DateTime? preFilledEventDate;

  const CreateCountdownScreen({
    super.key,
    this.preFilledEventName,
    this.preFilledCategory,
    this.preFilledEventDate,
  });

  @override
  State<CreateCountdownScreen> createState() => _CreateCountdownScreenState();
}

class _CreateCountdownScreenState extends State<CreateCountdownScreen> {
  final _eventNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _eventNameFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  
  DateTime? _selectedDate;
  String? _selectedCategory;
  bool _isCreating = false;
  
  final List<String> _categories = [
    'ゲーム',
    '音楽',
    'アニメ',
    'ライブ',
    '推し活',
    'その他'
  ];

  @override
  void initState() {
    super.initState();
    // 事前入力データがあれば設定
    if (widget.preFilledEventName != null) {
      _eventNameController.text = widget.preFilledEventName!;
    }
    if (widget.preFilledCategory != null) {
      _selectedCategory = widget.preFilledCategory;
    }
    if (widget.preFilledEventDate != null) {
      _selectedDate = widget.preFilledEventDate;
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _descriptionController.dispose();
    _eventNameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Color _getUnifiedColor() {
    return const Color(0xFF1DA1F2); // Twitterブルーで統一
  }

  bool get _canCreate {
    return _eventNameController.text.trim().isNotEmpty &&
           _selectedDate != null &&
           _selectedCategory != null &&
           !_isCreating;
  }

  List<String> _extractHashtags(String text) {
    final regex = RegExp(r'#[^\s#]+');
    final matches = regex.allMatches(text);
    return matches.map((match) => match.group(0)!.substring(1)).toList();
  }

  Widget _buildHashtagPreview() {
    final hashtags = _extractHashtags(_descriptionController.text);
    if (hashtags.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ハッシュタグ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1DA1F2),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: hashtags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DA1F2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '#$tag',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1DA1F2),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: _getUnifiedColor()),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(seedColor: _getUnifiedColor()),
            ),
            child: child!,
          );
        },
      );
      
      if (time != null) {
        setState(() {
          _selectedDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _createCountdown() async {
    if (!_canCreate) return;

    setState(() {
      _isCreating = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カウントダウンを作成するにはログインが必要です。')),
      );
      setState(() {
        _isCreating = false;
      });
      return;
    }

    try {
      final description = _descriptionController.text.trim().isNotEmpty 
          ? _descriptionController.text.trim() 
          : null;
      print('CreateCountdown - Description: "$description"'); // デバッグ用
      print('CreateCountdown - Description controller text: "${_descriptionController.text}"'); // デバッグ用
      
      final newCountdown = Countdown(
        id: '',
        eventName: _eventNameController.text.trim(),
        description: description,
        eventDate: _selectedDate!,
        category: _selectedCategory!,
        creatorId: user.uid,
        participantsCount: 1,
      );

      // 🚀 統一パイプライン: カウントダウン作成イベント送信
      final success = await CountdownService.createCountdownEvent(newCountdown);
      
      if (!success) {
        throw Exception('カウントダウン作成イベントの送信に失敗しました');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カウントダウンが作成されました！')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('作成に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
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
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '新しいカウントダウン',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: ElevatedButton(
              onPressed: _canCreate ? _createCountdown : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canCreate ? _getUnifiedColor() : Colors.grey[300],
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '作成',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // メイン入力エリア
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // プロフィールアイコン
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
                        // 入力フィールド
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // イベント名入力
                              TextField(
                                controller: _eventNameController,
                                focusNode: _eventNameFocusNode,
                                decoration: const InputDecoration(
                                  hintText: 'イベント名を入力',
                                  hintStyle: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(fontSize: 18),
                                onChanged: (value) => setState(() {}),
                              ),
                              // 説明文入力
                              TextField(
                                controller: _descriptionController,
                                focusNode: _descriptionFocusNode,
                                decoration: const InputDecoration(
                                  hintText: '詳細やハッシュタグを追加...',
                                  hintStyle: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(fontSize: 16),
                                maxLines: null,
                                onChanged: (value) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ハッシュタグプレビュー
                  _buildHashtagPreview(),
                  const Divider(height: 1, color: Colors.grey),
                  
                  // ツールバー
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // 画像追加ボタン（プレースホルダー）
                        IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('画像機能は今後実装予定です')),
                            );
                          },
                          icon: const Icon(
                            Icons.image_outlined,
                            color: Color(0xFF1DA1F2),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 日時選択ボタン
                        GestureDetector(
                          onTap: _selectDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedDate != null 
                                  ? const Color(0xFF1DA1F2).withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _selectedDate != null 
                                    ? const Color(0xFF1DA1F2)
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: _selectedDate != null 
                                      ? const Color(0xFF1DA1F2)
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedDate != null
                                      ? '${_selectedDate!.month}/${_selectedDate!.day} ${_selectedDate!.hour}:${_selectedDate!.minute.toString().padLeft(2, '0')}'
                                      : '日時選択',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _selectedDate != null 
                                        ? const Color(0xFF1DA1F2)
                                        : Colors.grey[600],
                                    fontWeight: _selectedDate != null 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        // カテゴリ選択
                        DropdownButton<String>(
                          value: _selectedCategory,
                          hint: Text(
                            'カテゴリ',
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                          underline: const SizedBox.shrink(),
                          items: _categories.map((String category) {
                            return DropdownMenuItem<String>(
                              value: category,
                              child: Text(
                                category,
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCategory = newValue;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}