import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api_service.dart';

class ContentModerationScreen extends StatefulWidget {
  const ContentModerationScreen({super.key});

  @override
  State<ContentModerationScreen> createState() => _ContentModerationScreenState();
}

class _ContentModerationScreenState extends State<ContentModerationScreen> {
  final _contentIdController = TextEditingController();
  String _selectedContentType = 'countdown';
  String _selectedAction = 'hidden_by_moderator';
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;
  String? _lastResult;

  @override
  void dispose() {
    _contentIdController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _moderateContent() async {
    if (_contentIdController.text.trim().isEmpty || _reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('コンテンツIDと理由を入力してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    setState(() {
      _isLoading = true;
      _lastResult = null;
    });

    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getIdToken();
    
    if (token == null) {
      setState(() {
        _isLoading = false;
        _lastResult = 'エラー: 認証に失敗しました';
      });
      return;
    }

    final apiService = AdminApiService(token);
    final response = await apiService.moderateContent(
      contentId: _contentIdController.text.trim(),
      contentType: _selectedContentType,
      newStatus: _selectedAction,
      reason: _reasonController.text.trim(),
      notes: _notesController.text.trim().isNotEmpty 
          ? _notesController.text.trim() 
          : null,
    );

    setState(() {
      _isLoading = false;
      if (response.success) {
        _lastResult = '✅ モデレーションが完了しました';
        _clearForm();
      } else {
        _lastResult = '❌ エラー: ${response.error}';
      }
    });
  }

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('モデレーション確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('以下の内容でモデレーションを実行しますか？'),
            const SizedBox(height: 16),
            Text('コンテンツID: ${_contentIdController.text.trim()}'),
            Text('タイプ: $_selectedContentType'),
            Text('アクション: ${_getActionText(_selectedAction)}'),
            Text('理由: ${_reasonController.text.trim()}'),
            if (_notesController.text.trim().isNotEmpty)
              Text('メモ: ${_notesController.text.trim()}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('実行'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _clearForm() {
    _contentIdController.clear();
    _reasonController.clear();
    _notesController.clear();
    setState(() {
      _selectedContentType = 'countdown';
      _selectedAction = 'hidden_by_moderator';
    });
  }

  String _getActionText(String action) {
    switch (action) {
      case 'visible':
        return '表示';
      case 'hidden_by_moderator':
        return '運営により非表示';
      case 'deleted_by_user':
        return 'ユーザーにより削除';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('コンテンツモデレーション'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'コンテンツモデレーション',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '不適切なコンテンツの表示状態を変更します',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'コンテンツ情報',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contentIdController,
                        decoration: const InputDecoration(
                          labelText: 'コンテンツID *',
                          hintText: 'カウントダウンまたはコメントのID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedContentType,
                              decoration: const InputDecoration(
                                labelText: 'コンテンツタイプ',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'countdown',
                                  child: Text('カウントダウン'),
                                ),
                                DropdownMenuItem(
                                  value: 'comment',
                                  child: Text('コメント'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedContentType = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'モデレーション設定',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedAction,
                        decoration: const InputDecoration(
                          labelText: '新しいステータス',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'visible',
                            child: Text('表示 (復活)'),
                          ),
                          DropdownMenuItem(
                            value: 'hidden_by_moderator',
                            child: Text('運営により非表示'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedAction = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _reasonController,
                        decoration: const InputDecoration(
                          labelText: '理由 *',
                          hintText: '例: 利用規約違反のため',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: '内部メモ (任意)',
                          hintText: '管理者向けの追加情報',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _clearForm,
                            child: const Text('クリア'),
                          ),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _moderateContent,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                            ),
                            child: _isLoading
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text('処理中...'),
                                    ],
                                  )
                                : const Text('モデレーション実行'),
                          ),
                        ],
                      ),
                      if (_lastResult != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _lastResult!.startsWith('✅')
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            border: Border.all(
                              color: _lastResult!.startsWith('✅')
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_lastResult!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⚠️ 注意事項',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• モデレーション操作は取り消すことができません',
                        style: TextStyle(fontSize: 14),
                      ),
                      const Text(
                        '• 全ての操作は監査ログに記録されます',
                        style: TextStyle(fontSize: 14),
                      ),
                      const Text(
                        '• 必ず理由を明確に記載してください',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}