#!/usr/bin/env python3
"""
Firestore to Redis Data Migration Script
========================================

1回限りのデータ移行スクリプト
- 既存のcountsコレクションやdistributed_countersシャードの値を集計
- Redisに初期データを投入
- データ整合性検証

使用方法:
    python firestore_to_redis_migration.py --dry-run  # 実行前の確認
    python firestore_to_redis_migration.py --migrate  # 実際の移行実行
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict

import redis
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from google.auth import default

# ログ設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'migration_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class CountdownData:
    """カウントダウンデータ構造"""
    countdown_id: str
    event_name: str
    description: str
    event_date: datetime
    category: str
    image_url: Optional[str]
    creator_id: str
    participants_count: int
    likes_count: int
    comments_count: int
    views_count: int
    recent_comments_count: int
    recent_likes_count: int
    recent_views_count: int
    trend_score: float
    last_aggregated_at: datetime

@dataclass
class DistributedCounterData:
    """分散カウンターデータ構造"""
    countdown_id: str
    counter_type: str
    shard_index: int
    count: int
    created_at: datetime
    last_updated: datetime
    needs_aggregation: bool
    migrated: bool

@dataclass
class TrendRankingData:
    """トレンドランキングデータ構造"""
    countdown_id: str
    event_name: str
    category: str
    event_date: datetime
    participants_count: int
    comments_count: int
    shares_count: int
    trend_score: float
    rank: int
    updated_at: datetime

@dataclass
class MigrationStats:
    """移行統計情報"""
    total_countdowns: int = 0
    total_distributed_counters: int = 0
    total_trend_rankings: int = 0
    successful_migrations: int = 0
    failed_migrations: int = 0
    data_inconsistencies: int = 0
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None

class FirestoreToRedisMigration:
    """Firestore to Redis データ移行クラス"""
    
    def __init__(self, redis_host: str = None, redis_port: int = 6379):
        # 環境変数から設定を取得（Docker環境対応）
        if redis_host is None:
            redis_host = os.getenv('REDIS_HOST', 'localhost')
        redis_port = int(os.getenv('REDIS_PORT', redis_port))
        self.db = firestore.Client()
        self.redis_client = redis.Redis(
            host=redis_host,
            port=redis_port,
            decode_responses=True
        )
        self.stats = MigrationStats()
        
    def connect_and_verify(self) -> bool:
        """
        接続確認とサービス状態検証
        
        Returns:
            bool: 接続成功の場合True
        """
        try:
            # Firestore接続確認
            test_doc = self.db.collection('test').document('connection_test')
            test_doc.set({'timestamp': datetime.now()})
            test_doc.delete()
            logger.info("✅ Firestore接続確認完了")
            
            # Redis接続確認
            self.redis_client.ping()
            logger.info("✅ Redis接続確認完了")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ 接続エラー: {e}")
            return False
    
    def fetch_existing_data(self) -> Tuple[List[CountdownData], List[DistributedCounterData], List[TrendRankingData]]:
        """
        既存のFirestoreデータを取得
        
        Returns:
            Tuple[List[CountdownData], List[DistributedCounterData], List[TrendRankingData]]:
                取得したデータのリスト
        """
        logger.info("🔍 既存データの取得開始...")
        
        # countsコレクションの取得
        counts_data = []
        try:
            counts_ref = self.db.collection('counts')
            counts_docs = counts_ref.stream()
            
            for doc in counts_docs:
                data = doc.to_dict()
                countdown_data = CountdownData(
                    countdown_id=doc.id,
                    event_name=data.get('eventName', ''),
                    description=data.get('description', ''),
                    event_date=data.get('eventDate', datetime.now()),
                    category=data.get('category', ''),
                    image_url=data.get('imageUrl'),
                    creator_id=data.get('creatorId', ''),
                    participants_count=data.get('participantsCount', 0),
                    likes_count=data.get('likesCount', 0),
                    comments_count=data.get('commentsCount', 0),
                    views_count=data.get('viewsCount', 0),
                    recent_comments_count=data.get('recentCommentsCount', 0),
                    recent_likes_count=data.get('recentLikesCount', 0),
                    recent_views_count=data.get('recentViewsCount', 0),
                    trend_score=data.get('trendScore', 0.0),
                    last_aggregated_at=data.get('lastAggregatedAt', datetime.now())
                )
                counts_data.append(countdown_data)
                
            self.stats.total_countdowns = len(counts_data)
            logger.info(f"📊 countsコレクション: {len(counts_data)}件")
            
        except Exception as e:
            logger.error(f"❌ countsコレクション取得エラー: {e}")
        
        # distributed_countersコレクションの取得
        distributed_counters_data = []
        try:
            distributed_counters_ref = self.db.collection('distributed_counters')
            distributed_counters_docs = distributed_counters_ref.stream()
            
            for doc in distributed_counters_docs:
                data = doc.to_dict()
                counter_data = DistributedCounterData(
                    countdown_id=data.get('countdownId', ''),
                    counter_type=data.get('counterType', ''),
                    shard_index=data.get('shardIndex', 0),
                    count=data.get('count', 0),
                    created_at=data.get('createdAt', datetime.now()),
                    last_updated=data.get('lastUpdated', datetime.now()),
                    needs_aggregation=data.get('needsAggregation', False),
                    migrated=data.get('migrated', False)
                )
                distributed_counters_data.append(counter_data)
                
            self.stats.total_distributed_counters = len(distributed_counters_data)
            logger.info(f"📊 distributed_countersコレクション: {len(distributed_counters_data)}件")
            
        except Exception as e:
            logger.error(f"❌ distributed_countersコレクション取得エラー: {e}")
        
        # trendRankingsコレクションの取得
        trend_rankings_data = []
        try:
            trend_rankings_ref = self.db.collection('trendRankings')
            trend_rankings_docs = trend_rankings_ref.stream()
            
            for doc in trend_rankings_docs:
                data = doc.to_dict()
                ranking_data = TrendRankingData(
                    countdown_id=data.get('countdownId', ''),
                    event_name=data.get('eventName', ''),
                    category=data.get('category', ''),
                    event_date=data.get('eventDate', datetime.now()),
                    participants_count=data.get('participantsCount', 0),
                    comments_count=data.get('commentsCount', 0),
                    shares_count=data.get('sharesCount', 0),
                    trend_score=data.get('trendScore', 0.0),
                    rank=data.get('rank', 0),
                    updated_at=data.get('updatedAt', datetime.now())
                )
                trend_rankings_data.append(ranking_data)
                
            self.stats.total_trend_rankings = len(trend_rankings_data)
            logger.info(f"📊 trendRankingsコレクション: {len(trend_rankings_data)}件")
            
        except Exception as e:
            logger.error(f"❌ trendRankingsコレクション取得エラー: {e}")
        
        return counts_data, distributed_counters_data, trend_rankings_data
    
    def aggregate_distributed_counters(self, distributed_counters: List[DistributedCounterData]) -> Dict[str, Dict[str, int]]:
        """
        分散カウンターを集計
        
        Args:
            distributed_counters: 分散カウンターデータのリスト
            
        Returns:
            Dict[str, Dict[str, int]]: {countdown_id: {counter_type: total_count}}
        """
        logger.info("🔄 分散カウンターの集計開始...")
        
        aggregated = {}
        
        for counter in distributed_counters:
            countdown_id = counter.countdown_id
            counter_type = counter.counter_type
            
            if countdown_id not in aggregated:
                aggregated[countdown_id] = {}
            
            if counter_type not in aggregated[countdown_id]:
                aggregated[countdown_id][counter_type] = 0
            
            aggregated[countdown_id][counter_type] += counter.count
        
        logger.info(f"📊 分散カウンター集計完了: {len(aggregated)}件のカウントダウン")
        
        return aggregated
    
    def validate_data_consistency(self, counts_data: List[CountdownData], 
                                aggregated_counters: Dict[str, Dict[str, int]]) -> List[str]:
        """
        データ整合性検証
        
        Args:
            counts_data: countsコレクションデータ
            aggregated_counters: 集計済み分散カウンターデータ
            
        Returns:
            List[str]: 不整合のあるカウントダウンIDのリスト
        """
        logger.info("🔍 データ整合性検証開始...")
        
        inconsistencies = []
        
        for countdown in counts_data:
            countdown_id = countdown.countdown_id
            
            if countdown_id in aggregated_counters:
                aggregated = aggregated_counters[countdown_id]
                
                # 各カウンターの整合性をチェック
                counter_types = ['likes', 'comments', 'participants']
                
                for counter_type in counter_types:
                    if counter_type in aggregated:
                        counts_value = getattr(countdown, f'{counter_type}_count', 0)
                        aggregated_value = aggregated[counter_type]
                        
                        if counts_value != aggregated_value:
                            inconsistencies.append(countdown_id)
                            logger.warning(
                                f"⚠️ 不整合検出: {countdown_id} の {counter_type} "
                                f"counts={counts_value}, aggregated={aggregated_value}"
                            )
                            break
        
        self.stats.data_inconsistencies = len(inconsistencies)
        logger.info(f"📊 データ整合性検証完了: {len(inconsistencies)}件の不整合")
        
        return inconsistencies
    
    def migrate_to_redis(self, counts_data: List[CountdownData], 
                        trend_rankings_data: List[TrendRankingData],
                        aggregated_counters: Dict[str, Dict[str, int]]) -> bool:
        """
        Redisにデータをマイグレーション
        
        Args:
            counts_data: countsコレクションデータ
            trend_rankings_data: trendRankingsコレクションデータ
            aggregated_counters: 集計済み分散カウンターデータ
            
        Returns:
            bool: 移行成功の場合True
        """
        logger.info("🚀 Redis移行開始...")
        
        try:
            # パイプラインを使用してバッチ処理
            pipe = self.redis_client.pipeline()
            
            # カウントダウンデータの移行
            for countdown in counts_data:
                countdown_id = countdown.countdown_id
                
                # メインのカウントダウンデータ
                countdown_key = f"countdown:{countdown_id}"
                countdown_data = asdict(countdown)
                # datetimeオブジェクトを文字列に変換
                countdown_data['event_date'] = countdown_data['event_date'].isoformat()
                countdown_data['last_aggregated_at'] = countdown_data['last_aggregated_at'].isoformat()
                
                pipe.hmset(countdown_key, countdown_data)
                
                # 各種カウンター値
                pipe.hset(f"counter:{countdown_id}", "likes", countdown.likes_count)
                pipe.hset(f"counter:{countdown_id}", "comments", countdown.comments_count)
                pipe.hset(f"counter:{countdown_id}", "participants", countdown.participants_count)
                pipe.hset(f"counter:{countdown_id}", "views", countdown.views_count)
                
                # 最近のカウンター値
                pipe.hset(f"recent_counter:{countdown_id}", "likes", countdown.recent_likes_count)
                pipe.hset(f"recent_counter:{countdown_id}", "comments", countdown.recent_comments_count)
                pipe.hset(f"recent_counter:{countdown_id}", "views", countdown.recent_views_count)
                
                # トレンドスコア
                pipe.zadd("trend_scores", {countdown_id: countdown.trend_score})
                
                # カテゴリ別インデックス
                pipe.sadd(f"category:{countdown.category}", countdown_id)
                
                self.stats.successful_migrations += 1
            
            # トレンドランキングデータの移行
            for ranking in trend_rankings_data:
                ranking_key = f"ranking:{ranking.countdown_id}"
                ranking_data = asdict(ranking)
                # datetimeオブジェクトを文字列に変換
                ranking_data['event_date'] = ranking_data['event_date'].isoformat()
                ranking_data['updated_at'] = ranking_data['updated_at'].isoformat()
                
                pipe.hmset(ranking_key, ranking_data)
                
                # ランキング用sorted set
                pipe.zadd(f"ranking:{ranking.category}", {ranking.countdown_id: ranking.rank})
            
            # 集計済み分散カウンターの適用
            for countdown_id, counters in aggregated_counters.items():
                for counter_type, count in counters.items():
                    pipe.hset(f"counter:{countdown_id}", counter_type, count)
            
            # 一括実行
            pipe.execute()
            
            logger.info("✅ Redis移行完了")
            return True
            
        except Exception as e:
            logger.error(f"❌ Redis移行エラー: {e}")
            self.stats.failed_migrations += 1
            return False
    
    def create_migration_report(self) -> str:
        """
        移行レポートの作成
        
        Returns:
            str: 移行レポート（JSON形式）
        """
        if self.stats.end_time and self.stats.start_time:
            duration = (self.stats.end_time - self.stats.start_time).total_seconds()
        else:
            duration = 0
        
        report = {
            "migration_timestamp": datetime.now().isoformat(),
            "statistics": asdict(self.stats),
            "duration_seconds": duration,
            "success_rate": (self.stats.successful_migrations / max(1, self.stats.total_countdowns)) * 100
        }
        
        return json.dumps(report, indent=2, default=str)
    
    def run_migration(self, dry_run: bool = False) -> bool:
        """
        移行実行
        
        Args:
            dry_run: テスト実行の場合True
            
        Returns:
            bool: 移行成功の場合True
        """
        self.stats.start_time = datetime.now()
        
        logger.info("🚀 Firestore to Redis データ移行開始")
        logger.info(f"📋 実行モード: {'DRY RUN' if dry_run else 'LIVE MIGRATION'}")
        
        # 接続確認
        if not self.connect_and_verify():
            return False
        
        # データ取得
        counts_data, distributed_counters_data, trend_rankings_data = self.fetch_existing_data()
        
        # 分散カウンターの集計
        aggregated_counters = self.aggregate_distributed_counters(distributed_counters_data)
        
        # データ整合性検証
        inconsistencies = self.validate_data_consistency(counts_data, aggregated_counters)
        
        if inconsistencies:
            logger.warning(f"⚠️ {len(inconsistencies)}件の不整合が検出されました")
            if not dry_run:
                response = input("続行しますか？ (y/N): ")
                if response.lower() != 'y':
                    logger.info("移行を中止しました")
                    return False
        
        # 実際の移行実行
        if not dry_run:
            success = self.migrate_to_redis(counts_data, trend_rankings_data, aggregated_counters)
            if not success:
                return False
        
        self.stats.end_time = datetime.now()
        
        # レポート作成
        report = self.create_migration_report()
        
        # レポートファイル保存
        report_filename = f"migration_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_filename, 'w', encoding='utf-8') as f:
            f.write(report)
        
        logger.info(f"📊 移行レポートを保存: {report_filename}")
        logger.info("✅ 移行完了")
        
        return True

def main():
    """メイン関数"""
    parser = argparse.ArgumentParser(description='Firestore to Redis データ移行')
    parser.add_argument('--dry-run', action='store_true', help='テスト実行（実際の移行は行わない）')
    parser.add_argument('--migrate', action='store_true', help='実際の移行を実行')
    parser.add_argument('--redis-host', default='localhost', help='Redisサーバーホスト')
    parser.add_argument('--redis-port', type=int, default=6379, help='Redisサーバーポート')
    
    args = parser.parse_args()
    
    if not args.dry_run and not args.migrate:
        parser.error("--dry-run または --migrate のいずれかを指定してください")
    
    # 移行実行
    migration = FirestoreToRedisMigration(
        redis_host=args.redis_host,
        redis_port=args.redis_port
    )
    
    success = migration.run_migration(dry_run=args.dry_run)
    
    if success:
        logger.info("🎉 移行が正常に完了しました")
        sys.exit(0)
    else:
        logger.error("❌ 移行に失敗しました")
        sys.exit(1)

if __name__ == "__main__":
    main()