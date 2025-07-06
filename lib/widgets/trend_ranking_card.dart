import 'package:flutter/material.dart';
import '../models/trend_ranking.dart';
import '../screens/thread_screen.dart';
import '../models/countdown.dart';

class TrendRankingCard extends StatelessWidget {
  final TrendRanking ranking;
  final bool showRank;

  const TrendRankingCard({
    super.key,
    required this.ranking,
    this.showRank = true,
  });

  Color _getCategoryColor() {
    switch (ranking.category) {
      case 'ゲーム':
        return Colors.blue;
      case '音楽':
        return Colors.purple;
      case 'アニメ':
        return Colors.orange;
      case 'ライブ':
        return Colors.red;
      case '推し活':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRankBadge() {
    Color badgeColor;
    if (ranking.rank == 1) {
      badgeColor = Colors.amber;
    } else if (ranking.rank == 2) {
      badgeColor = Colors.grey[400]!;
    } else if (ranking.rank == 3) {
      badgeColor = Colors.brown[300]!;
    } else {
      badgeColor = Colors.grey[600]!;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${ranking.rank}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatTimeRemaining() {
    final now = DateTime.now();
    final difference = ranking.eventDate.difference(now);
    
    if (difference.isNegative) {
      return "イベント終了";
    }
    
    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    
    if (days > 0) {
      return "あと${days}日";
    } else if (hours > 0) {
      return "あと${hours}時間";
    } else if (minutes > 0) {
      return "あと${minutes}分";
    } else {
      return "まもなく開始！";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TrendRankingからCountdownを作成してThreadScreenに渡す
          final countdown = Countdown(
            id: ranking.countdownId,
            eventName: ranking.eventName,
            eventDate: ranking.eventDate,
            category: ranking.category,
            imageUrl: '',
            creatorId: '',
            participantsCount: ranking.participantsCount,
          );
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ThreadScreen(countdown: countdown),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ランクバッジ
              if (showRank) ...[
                _buildRankBadge(),
                const SizedBox(width: 12),
              ],
              
              // イベント情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ranking.category,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimeRemaining(),
                          style: TextStyle(
                            color: _getCategoryColor(),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ranking.eventName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 2),
                        Text(
                          '${ranking.participantsCount}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 2),
                        Text(
                          '${ranking.commentsCount}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.trending_up, size: 12, color: Colors.red[600]),
                              const SizedBox(width: 2),
                              Text(
                                '${ranking.trendScore.toInt()}',
                                style: TextStyle(
                                  color: Colors.red[600],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
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
            ],
          ),
        ),
      ),
    );
  }
}