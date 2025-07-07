import 'package:flutter/material.dart';
import '../services/report_service.dart';

class ReportDialog extends StatefulWidget {
  final String contentId;
  final String contentType;
  final String contentTitle;

  const ReportDialog({
    super.key,
    required this.contentId,
    required this.contentType,
    required this.contentTitle,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通報理由を選択してください'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final success = await ReportService.reportContent(
      contentId: widget.contentId,
      contentType: widget.contentType,
      reason: _selectedReason!,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
    );

    setState(() {
      _isSubmitting = false;
    });

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通報を送信しました'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通報の送信に失敗しました'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('投稿を通報'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '「${widget.contentTitle}」を通報しますか？',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              '通報理由を選択してください:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...ReportService.getReportReasons().map((reason) {
              return RadioListTile<String>(
                title: Text(reason),
                value: reason,
                groupValue: _selectedReason,
                onChanged: (value) {
                  setState(() {
                    _selectedReason = value;
                  });
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '詳細説明 (任意)',
                hintText: '具体的な問題点があれば記載してください',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            const Text(
              '※ 通報内容は運営チームが確認し、適切に対応いたします',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('通報する'),
        ),
      ],
    );
  }
}

/// 通報ボタンを表示するためのヘルパー関数
Future<void> showReportDialog({
  required BuildContext context,
  required String contentId,
  required String contentType,
  required String contentTitle,
}) async {
  // まず、ユーザーが既に通報済みかチェック
  final hasReported = await ReportService.hasUserReported(
    contentId: contentId,
  );

  if (!context.mounted) return;

  if (hasReported) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('このコンテンツは既に通報済みです'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // 通報ダイアログを表示
  await showDialog<bool>(
    context: context,
    builder: (context) => ReportDialog(
      contentId: contentId,
      contentType: contentType,
      contentTitle: contentTitle,
    ),
  );
}