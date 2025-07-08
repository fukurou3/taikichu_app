import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api_service.dart';
import '../../../lib/services/moderation_logs_service.dart';
import 'package:intl/intl.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  List<ModerationLog> _logs = [];
  bool _isLoading = false;
  String? _error;
  
  // フィルター設定
  String? _selectedAdminUid;
  String? _selectedTargetType;
  String? _selectedAction;
  DateTimeRange? _selectedDateRange;
  final TextEditingController _targetIdController = TextEditingController();
  
  // ページネーション
  bool _hasMore = true;
  String? _lastDocumentId;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  @override
  void dispose() {
    _targetIdController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditLogs({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _logs.clear();
        _lastDocumentId = null;
        _hasMore = true;
      }
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final token = await authProvider.getIdToken();
      final apiService = AdminApiService(token);

      final response = await apiService.getAuditLogs(
        adminUid: _selectedAdminUid,
        targetType: _selectedTargetType,
        targetId: _targetIdController.text.isNotEmpty ? _targetIdController.text : null,
        action: _selectedAction,
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
        limit: 20,
        lastDocumentId: _lastDocumentId,
      );

      if (response.success && response.data != null) {
        final newLogs = response.data!;
        
        setState(() {
          if (refresh) {
            _logs = newLogs;
          } else {
            _logs.addAll(newLogs);
          }
          
          _hasMore = newLogs.length == 20;
          if (newLogs.isNotEmpty) {
            _lastDocumentId = newLogs.last.id;
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.error ?? '監査ログの取得に失敗しました';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'エラーが発生しました: $e';
        _isLoading = false;
      });
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フィルター設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 対象管理者
              DropdownButtonFormField<String>(
                value: _selectedAdminUid,
                decoration: const InputDecoration(labelText: '管理者'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('すべて')),
                  // 実際のアプリでは管理者一覧を動的に取得
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedAdminUid = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // 対象タイプ
              DropdownButtonFormField<String>(
                value: _selectedTargetType,
                decoration: const InputDecoration(labelText: '対象タイプ'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('すべて')),
                  DropdownMenuItem(value: 'user', child: Text('ユーザー')),
                  DropdownMenuItem(value: 'countdown', child: Text('カウントダウン')),
                  DropdownMenuItem(value: 'comment', child: Text('コメント')),
                  DropdownMenuItem(value: 'report', child: Text('通報')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTargetType = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // アクション
              DropdownButtonFormField<String>(
                value: _selectedAction,
                decoration: const InputDecoration(labelText: 'アクション'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('すべて')),
                  DropdownMenuItem(value: 'user_ban', child: Text('ユーザーBAN')),
                  DropdownMenuItem(value: 'content_delete', child: Text('コンテンツ削除')),
                  DropdownMenuItem(value: 'content_hide', child: Text('コンテンツ非表示')),
                  DropdownMenuItem(value: 'report_resolve', child: Text('通報解決')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedAction = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // 対象ID
              TextField(
                controller: _targetIdController,
                decoration: const InputDecoration(
                  labelText: '対象ID',
                  hintText: '特定のIDで検索',
                ),
              ),
              const SizedBox(height: 16),
              
              // 日付範囲
              ListTile(
                title: const Text('日付範囲'),
                subtitle: Text(_selectedDateRange != null
                    ? '${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}'
                    : '指定なし'),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final dateRange = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                    initialDateRange: _selectedDateRange,
                  );
                  if (dateRange != null) {
                    setState(() {
                      _selectedDateRange = dateRange;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedAdminUid = null;
                _selectedTargetType = null;
                _selectedAction = null;
                _selectedDateRange = null;
                _targetIdController.clear();
              });
              Navigator.of(context).pop();
              _loadAuditLogs(refresh: true);
            },
            child: const Text('クリア'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadAuditLogs(refresh: true);
            },
            child: const Text('適用'),
          ),
        ],
      ),
    );
  }

  void _showLogDetails(ModerationLog log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('監査ログ詳細'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('アクション', log.action),
              _buildDetailRow('対象タイプ', log.targetType),
              _buildDetailRow('対象ID', log.targetId),
              _buildDetailRow('理由', log.reason),
              _buildDetailRow('管理者UID', log.adminUid),
              if (log.adminEmail != null)
                _buildDetailRow('管理者メール', log.adminEmail!),
              _buildDetailRow('実行日時', DateFormat('yyyy/MM/dd HH:mm:ss').format(log.timestamp)),
              _buildDetailRow('重要度', log.severity),
              _buildDetailRow('承認要否', log.requiresApproval ? '要' : '不要'),
              if (log.notes != null)
                _buildDetailRow('備考', log.notes!),
              if (log.previousState != null)
                _buildDetailRow('変更前', log.previousState!),
              if (log.newState != null)
                _buildDetailRow('変更後', log.newState!),
              if (log.ipAddress != null)
                _buildDetailRow('IPアドレス', log.ipAddress!),
              if (log.metadata != null) ...[
                const SizedBox(height: 16),
                const Text('メタデータ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.metadata.toString(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'HIGH':
        return Colors.red;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String action) {
    if (action.contains('ban')) return Icons.block;
    if (action.contains('delete')) return Icons.delete;
    if (action.contains('hide')) return Icons.visibility_off;
    if (action.contains('search')) return Icons.search;
    if (action.contains('review')) return Icons.rate_review;
    return Icons.admin_panel_settings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('監査ログ'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'フィルター',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadAuditLogs(refresh: true),
            tooltip: '更新',
          ),
        ],
      ),
      body: Column(
        children: [
          // フィルター表示
          if (_selectedAdminUid != null ||
              _selectedTargetType != null ||
              _selectedAction != null ||
              _selectedDateRange != null ||
              _targetIdController.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('適用中のフィルター:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_selectedTargetType != null)
                        Chip(label: Text('タイプ: $_selectedTargetType')),
                      if (_selectedAction != null)
                        Chip(label: Text('アクション: $_selectedAction')),
                      if (_targetIdController.text.isNotEmpty)
                        Chip(label: Text('ID: ${_targetIdController.text}')),
                      if (_selectedDateRange != null)
                        Chip(label: Text('期間: ${DateFormat('MM/dd').format(_selectedDateRange!.start)}-${DateFormat('MM/dd').format(_selectedDateRange!.end)}')),
                    ],
                  ),
                ],
              ),
            ),

          // エラー表示
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red[50],
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  TextButton(
                    onPressed: () => _loadAuditLogs(refresh: true),
                    child: const Text('再試行'),
                  ),
                ],
              ),
            ),

          // ログリスト
          Expanded(
            child: _logs.isEmpty && !_isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('監査ログがありません'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _logs.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _logs.length) {
                        // ローディングインディケーター
                        if (_isLoading) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        } else {
                          // もっと読み込むボタン
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: ElevatedButton(
                              onPressed: () => _loadAuditLogs(),
                              child: const Text('さらに読み込む'),
                            ),
                          );
                        }
                      }

                      final log = _logs[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getSeverityColor(log.severity).withOpacity(0.2),
                            child: Icon(
                              _getActionIcon(log.action),
                              color: _getSeverityColor(log.severity),
                            ),
                          ),
                          title: Text(
                            log.action,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${log.targetType}: ${log.targetId}'),
                              Text('理由: ${log.reason}'),
                              Text(
                                '実行: ${DateFormat('MM/dd HH:mm').format(log.timestamp)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getSeverityColor(log.severity),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  log.severity,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (log.requiresApproval)
                                const Icon(
                                  Icons.warning,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                            ],
                          ),
                          onTap: () => _showLogDetails(log),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}