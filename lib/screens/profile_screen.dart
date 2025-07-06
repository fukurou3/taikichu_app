import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Container(
      color: Colors.white,
      child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF1DA1F2).withOpacity(0.1),
                  child: const Icon(
                    Icons.person,
                    size: 60,
                    color: Color(0xFF1DA1F2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.isAnonymous == true ? '匿名ユーザー' : 'ユーザー',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'UID: ${user?.uid ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('設定'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('設定画面は準備中です')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('ヘルプ'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ヘルプ画面は準備中です')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('アプリについて'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('待機中。'),
                  content: const Text('トレンド連動型カウントダウンSNSアプリ'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}