import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api_service.dart';
import 'audit_logs_screen.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final token = await authProvider.getIdToken();
      final apiService = AdminApiService(token);

      final response = await apiService.getAdminStats(
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now(),
      );

      if (response.success && response.data != null) {
        setState(() {
          _stats = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.error ?? '統計情報の取得に失敗しました';
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

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    final recentActions = _stats['recent_actions'] as List?;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '最近の活動',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AuditLogsScreen(),
                      ),
                    );
                  },
                  child: const Text('全て見る'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (recentActions != null && recentActions.isNotEmpty)
              ...recentActions.take(5).map((action) => _buildActivityItem(action))
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '最近の活動がありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> action) {
    final timestamp = action['timestamp'] != null 
        ? DateTime.parse(action['timestamp']) 
        : DateTime.now();
    
    Color severityColor = Colors.grey;
    if (action['severity'] == 'HIGH') severityColor = Colors.red;
    if (action['severity'] == 'MEDIUM') severityColor = Colors.orange;
    if (action['severity'] == 'LOW') severityColor = Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: severityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action['action'] ?? 'Unknown Action',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${action['target_type']}: ${action['target_id']}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('MM/dd HH:mm').format(timestamp),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTopModeratorsCard() {
    final topModerators = _stats['top_moderators'] as List?;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.leaderboard, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'アクティブな管理者 (今月)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topModerators != null && topModerators.isNotEmpty)
              ...topModerators.take(5).map((moderator) => _buildModeratorItem(moderator))
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'データがありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeratorItem(Map<String, dynamic> moderator) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.withOpacity(0.2),
            child: Text(
              (moderator['admin_email'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moderator['admin_email'] ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${moderator['action_count']} 件の操作',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${moderator['action_count']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理者ダッシュボード'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            tooltip: '更新',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'audit_logs':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AuditLogsScreen(),
                    ),
                  );
                  break;
                case 'logout':
                  authProvider.signOut();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'audit_logs',
                child: Row(
                  children: [
                    Icon(Icons.assignment),
                    SizedBox(width: 8),
                    Text('監査ログ'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('ログアウト'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('エラーが発生しました'),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadStats,
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ユーザー情報
                        Card(
                          color: Colors.blue[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.blue[800],
                                  child: const Icon(Icons.admin_panel_settings, color: Colors.white),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ようこそ、${authProvider.user?.email ?? "管理者"}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '権限: ${authProvider.isSuperAdmin ? "スーパー管理者" : "モデレーター"}',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 統計情報
                        const Text(
                          '統計情報 (過去30日)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.5,
                          children: [
                            _buildStatCard(
                              title: '総操作数',
                              value: '${_stats['total_actions'] ?? 0}',
                              icon: Icons.timeline,
                              color: Colors.blue,
                            ),
                            _buildStatCard(
                              title: '高リスク操作',
                              value: '${_stats['high_risk_actions'] ?? 0}',
                              icon: Icons.warning,
                              color: Colors.red,
                            ),
                            _buildStatCard(
                              title: 'ユーザーBAN',
                              value: '${_stats['user_bans'] ?? 0}',
                              icon: Icons.block,
                              color: Colors.orange,
                            ),
                            _buildStatCard(
                              title: 'コンテンツ削除',
                              value: '${_stats['content_deletions'] ?? 0}',
                              icon: Icons.delete,
                              color: Colors.purple,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // 最近の活動
                        _buildRecentActivityCard(),
                        const SizedBox(height: 24),

                        // アクティブな管理者
                        _buildTopModeratorsCard(),
                        const SizedBox(height: 24),

                        // クイックアクション
                        const Text(
                          'クイックアクション',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const AuditLogsScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.assignment),
                                label: const Text('監査ログ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[800],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('通報管理機能は準備中です')),
                                  );
                                },
                                icon: const Icon(Icons.report_problem),
                                label: const Text('通報管理'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange[800],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}