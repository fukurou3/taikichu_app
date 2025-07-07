import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Report> _reports = [];
  bool _isLoading = false;
  String _selectedStatus = 'pending';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getIdToken();
    
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '認証エラー';
      });
      return;
    }

    final apiService = AdminApiService(token);
    final response = await apiService.getReportedContents(
      status: _selectedStatus,
      limit: 50,
    );

    setState(() {
      _isLoading = false;
      if (response.success && response.data != null) {
        _reports = response.data!;
      } else {
        _errorMessage = response.error ?? '通報データの読み込みに失敗しました';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通報キュー'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('ステータス:'),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedStatus,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStatus = value;
                      });
                      _loadReports();
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('未処理')),
                    DropdownMenuItem(value: 'reviewed', child: Text('確認済み')),
                    DropdownMenuItem(value: 'resolved', child: Text('解決済み')),
                    DropdownMenuItem(value: 'all', child: Text('全て')),
                  ],
                ),
                const Spacer(),
                Text('${_reports.length}件の通報'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReports,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (_reports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('通報はありません'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (context, index) {
        final report = _reports[index];
        return ReportCard(
          report: report,
          onAction: (action) => _handleReportAction(report, action),
        );
      },
    );
  }

  Future<void> _handleReportAction(Report report, String action) async {
    // TODO: Implement report action handling
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action: ${report.id}')),
    );
  }
}

class ReportCard extends StatelessWidget {
  final Report report;
  final Function(String) onAction;

  const ReportCard({
    super.key,
    required this.report,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getContentIcon(report.contentType),
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'コンテンツID: ${report.contentId}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(_getStatusText(report.status)),
                  backgroundColor: _getStatusColor(report.status),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.report_problem, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('理由: ${report.reason ?? "未指定"}'),
              ],
            ),
            if (report.description != null && report.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                report.description!,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '通報日時: ${_formatDate(report.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onAction('view_content'),
                  child: const Text('コンテンツを確認'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => onAction('moderate'),
                  child: const Text('モデレート'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getContentIcon(String? contentType) {
    switch (contentType) {
      case 'countdown':
        return Icons.timer;
      case 'comment':
        return Icons.comment;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return '未処理';
      case 'reviewed':
        return '確認済み';
      case 'resolved':
        return '解決済み';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade100;
      case 'reviewed':
        return Colors.blue.shade100;
      case 'resolved':
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '不明';
    try {
      final date = DateTime.parse(dateString);
      return '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}