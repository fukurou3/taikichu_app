import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'login_modal.dart';

class CasualPostModal extends StatefulWidget {
  const CasualPostModal({super.key});

  @override
  State<CasualPostModal> createState() => _CasualPostModalState();
}

class _CasualPostModalState extends State<CasualPostModal> {
  final _tweetController = TextEditingController();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _tweetController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tweetController.dispose();
    super.dispose();
  }

  Future<void> _showLoginModal() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const LoginModal(),
    );
    
    if (result == true) {
      _postTweet();
    }
  }

  Future<void> _postTweet() async {
    if (_tweetController.text.trim().isEmpty) return;
    
    if (!AuthService.isLoggedIn) {
      _showLoginModal();
      return;
    }
    
    setState(() => _isPosting = true);
    try {
      await FirestoreService.createCasualPost(_tweetController.text.trim());
      
      _tweetController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('投稿に失敗しました: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'つぶやく',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder(
                  stream: AuthService.authStateChanges,
                  builder: (context, snapshot) {
                    return CircleAvatar(
                      backgroundColor: snapshot.hasData ? Colors.blue[100] : Colors.grey[300],
                      child: Icon(
                        Icons.person, 
                        color: snapshot.hasData ? Colors.blue : Colors.grey,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      StreamBuilder(
                        stream: AuthService.authStateChanges,
                        builder: (context, snapshot) {
                          return TextField(
                            controller: _tweetController,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: snapshot.hasData ? 'いまどうしてる？' : 'ツイートするにはログインしてください',
                              border: const OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 16),
                            onTap: snapshot.hasData ? null : _showLoginModal,
                            readOnly: !snapshot.hasData,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${280 - _tweetController.text.length}',
                            style: TextStyle(
                              color: _tweetController.text.length > 280 
                                  ? Colors.red 
                                  : Colors.grey,
                            ),
                          ),
                          StreamBuilder(
                            stream: AuthService.authStateChanges,
                            builder: (context, snapshot) {
                              final isLoggedIn = snapshot.hasData;
                              final hasText = _tweetController.text.trim().isNotEmpty;
                              
                              return ElevatedButton(
                                onPressed: (_isPosting || !hasText) ? null : _postTweet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: (isLoggedIn && hasText) ? Colors.blue[600] : Colors.grey[400],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                child: _isPosting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(isLoggedIn ? 'ツイート' : 'ログインして投稿'),
                              );
                            },
                          ),
                        ],
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
}