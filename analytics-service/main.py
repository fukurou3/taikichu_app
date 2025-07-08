#!/usr/bin/env python3
"""
MVP リアルタイム分析サービス (Cloud Run)

🎯 目的: Pub/Sub イベントを受信してRedisでリアルタイム集計
💰 コスト: Cloud Run は使用した分だけ課金（無料枠大）
⚡ 性能: Dataflow より軽量で十分な性能

アーキテクチャ:
Pub/Sub → このサービス → Redis → クライアント読み取り
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from functools import wraps

import redis
from flask import Flask, request, jsonify
from google.cloud import logging as cloud_logging
from google.cloud import error_reporting
from google.cloud import firestore
from firebase_admin import credentials, initialize_app, auth

# Firebase Admin SDK初期化
try:
    initialize_app()
except ValueError:
    # 既に初期化済みの場合は無視
    pass

# Cloud Logging設定
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Error Reporting クライアント初期化
error_client = error_reporting.Client()

app = Flask(__name__)

# グローバルエラーハンドラー
@app.errorhandler(Exception)
def handle_exception(e):
    """全ての未処理例外をError Reportingに送信"""
    try:
        # Error Reportingに報告
        error_client.report_exception()
        logger.exception(f"Unhandled exception: {e}")
    except Exception as report_error:
        logger.error(f"Failed to report error: {report_error}")
    
    return jsonify({
        'error': 'Internal server error',
        'timestamp': datetime.now(timezone.utc).isoformat()
    }), 500

# Redis接続設定
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
REDIS_PASSWORD = os.environ.get('REDIS_PASSWORD', None)

# Redis接続プール
redis_client = redis.ConnectionPool(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
    decode_responses=True,
    max_connections=20
)

# トレンドスコア重み設定
SCORE_WEIGHTS = {
    'like_added': 3.0,
    'like_removed': -3.0,
    'participation_added': 10.0,
    'participation_removed': -10.0,
    'comment_added': 5.0,
    'view': 1.0
}

# Redis キー設計
TREND_SCORE_KEY = "trend_score:{countdown_id}"
COUNTER_KEY = "counter:{type}:{countdown_id}"
RANKING_KEY = "ranking:{category}"
GLOBAL_RANKING_KEY = "ranking:global"

# ファンアウト・アーキテクチャ用 Redis キー
USER_FOLLOWS_KEY = "user_follows:{user_id}"
USER_FOLLOWERS_KEY = "user_followers:{user_id}"
FOLLOW_COUNT_KEY = "follow_count:{user_id}"
TIMELINE_KEY = "timeline:{user_id}"
GLOBAL_TIMELINE_KEY = "global_timeline"
TIMELINE_META_KEY = "timeline_meta:{user_id}"


class AnalyticsProcessor:
    """リアルタイム分析処理クラス"""
    
    def __init__(self):
        self.redis = redis.Redis(connection_pool=redis_client)
        
    def process_unified_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        統一イベント処理メソッド（新パイプライン）
        
        Args:
            event: 統一イベントデータ
            
        Returns:
            処理結果
        """
        start_time = time.time()
        
        try:
            # イベント検証
            event_type = event.get('type')
            countdown_id = event.get('countdownId') 
            user_id = event.get('userId')
            event_id = event.get('eventId', f"{countdown_id}_{event_type}_{int(time.time())}")
            
            if not all([event_type, countdown_id]):
                raise ValueError(f"Missing required fields: {event}")
            
            logger.info(f"[UNIFIED] Processing event: {event_type} for countdown {countdown_id}")
            
            # Redis パイプライン処理
            pipe = self.redis.pipeline()
            
            # 1. 重複チェック（同一イベントの重複実行防止）
            duplicate_key = f"processed:{event_id}"
            if self.redis.exists(duplicate_key):
                logger.warning(f"Duplicate event detected: {event_id}")
                return {
                    'success': True,
                    'message': 'Duplicate event ignored',
                    'event_id': event_id,
                    'execution_time': time.time() - start_time
                }
            
            # 重複防止マーク（5分間有効）
            pipe.setex(duplicate_key, 300, 1)
            
            # 2. トレンドスコア統一更新
            score_delta = SCORE_WEIGHTS.get(event_type, 0)
            if score_delta != 0:
                trend_key = TREND_SCORE_KEY.format(countdown_id=countdown_id)
                pipe.incrbyfloat(trend_key, score_delta)
                pipe.expire(trend_key, 86400 * 7)  # 7日間有効
                
                logger.debug(f"[UNIFIED] Trend score delta: {score_delta} for {countdown_id}")
            
            # 3. カウンター統一更新
            counter_type = self._get_counter_type(event_type)
            if counter_type:
                counter_key = COUNTER_KEY.format(type=counter_type, countdown_id=countdown_id)
                increment = 1 if 'added' in event_type or event_type == 'view' else -1
                pipe.incrby(counter_key, increment)
                pipe.expire(counter_key, 86400 * 30)  # 30日間有効
                
                logger.debug(f"[UNIFIED] Counter {counter_type}: {increment} for {countdown_id}")
            
            # 4. ランキング統一更新
            if score_delta != 0:
                # 現在のスコアを取得して更新
                current_score = self.redis.get(TREND_SCORE_KEY.format(countdown_id=countdown_id))
                if current_score is not None:
                    new_score = float(current_score) + score_delta
                    pipe.zadd(GLOBAL_RANKING_KEY, {countdown_id: new_score})
                    pipe.expire(GLOBAL_RANKING_KEY, 86400)  # 24時間有効
            
            # 5. ユーザー状態追跡（参加・いいね）
            if user_id:
                if event_type == 'participation_added':
                    user_participation_key = f"user_participation:{user_id}:{countdown_id}"
                    pipe.set(user_participation_key, 1)
                    pipe.expire(user_participation_key, 86400 * 30)  # 30日間有効
                elif event_type == 'participation_removed':
                    user_participation_key = f"user_participation:{user_id}:{countdown_id}"
                    pipe.delete(user_participation_key)
                elif event_type == 'like_added':
                    user_like_key = f"user_like:{user_id}:{countdown_id}"
                    pipe.set(user_like_key, 1)
                    pipe.expire(user_like_key, 86400 * 30)  # 30日間有効
                elif event_type == 'like_removed':
                    user_like_key = f"user_like:{user_id}:{countdown_id}"
                    pipe.delete(user_like_key)
                elif event_type == 'follow_toggle':
                    # フォロー/アンフォローイベントの処理
                    follow_event = {
                        'userId': user_id,
                        'targetUserId': countdown_id,  # この場合はtargetUserIdとして扱う
                        'action': event.get('eventData', {}).get('action', 'follow')
                    }
                    self.process_follow_event(follow_event)
                elif event_type == 'countdown_created':
                    # カウントダウン作成時のファンアウト処理
                    score = datetime.now(timezone.utc).timestamp()
                    self.fan_out_to_followers(user_id, countdown_id, score)
            
            # 6. 活動メタデータ更新
            metadata_key = f"activity:{countdown_id}"
            activity_data = {
                'last_event': event_type,
                'last_updated': datetime.now(timezone.utc).isoformat(),
                'event_count': 1,  # ハッシュフィールドの increment 用
            }
            if user_id:
                activity_data['last_user'] = user_id
                
            pipe.hset(metadata_key, activity_data)
            pipe.hincrby(metadata_key, 'event_count', 1)
            pipe.expire(metadata_key, 86400 * 7)  # 7日間有効
            
            # 7. 時間別集計（オプション）
            hour_key = f"hourly:{datetime.now(timezone.utc).strftime('%Y%m%d_%H')}:{event_type}"
            pipe.incr(hour_key)
            pipe.expire(hour_key, 86400 * 2)  # 48時間有効
            
            # パイプライン実行
            results = pipe.execute()
            
            execution_time = time.time() - start_time
            
            logger.info(f"[UNIFIED] Event processed successfully in {execution_time:.3f}s")
            
            return {
                'success': True,
                'event_id': event_id,
                'event_type': event_type,
                'countdown_id': countdown_id,
                'execution_time': execution_time,
                'pipeline_operations': len(results),
                'score_delta': score_delta,
                'counter_increment': increment if counter_type else 0
            }
            
        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"[UNIFIED] Error processing event in {execution_time:.3f}s: {e}")
            
            return {
                'success': False,
                'error': str(e),
                'event_type': event.get('type'),
                'countdown_id': event.get('countdownId'),
                'execution_time': execution_time
            }
    
    def process_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        レガシーイベント処理（後方互換性）
        
        Args:
            event: Pub/Subから受信したイベントデータ
            
        Returns:
            処理結果
        """
        # 統一処理に転送
        return self.process_unified_event(event)
    
    def _get_counter_type(self, event_type: str) -> Optional[str]:
        """イベントタイプからカウンタータイプを取得"""
        if 'like' in event_type:
            return 'likes'
        elif 'participation' in event_type:
            return 'participants'
        elif 'comment' in event_type:
            return 'comments'
        elif event_type == 'view':
            return 'views'
        return None
    
    def get_trend_score(self, countdown_id: str) -> float:
        """トレンドスコアを取得"""
        try:
            score = self.redis.get(TREND_SCORE_KEY.format(countdown_id=countdown_id))
            return float(score) if score else 0.0
        except Exception as e:
            logger.error(f"Error getting trend score for {countdown_id}: {e}")
            return 0.0
    
    def get_counter_value(self, countdown_id: str, counter_type: str) -> int:
        """カウンター値を取得"""
        try:
            value = self.redis.get(COUNTER_KEY.format(type=counter_type, countdown_id=countdown_id))
            return int(value) if value else 0
        except Exception as e:
            logger.error(f"Error getting {counter_type} count for {countdown_id}: {e}")
            return 0
    
    def get_ranking(self, category: str = None, limit: int = 20) -> list:
        """ランキングを取得"""
        try:
            ranking_key = RANKING_KEY.format(category=category) if category else GLOBAL_RANKING_KEY
            
            # スコア付きでトップを取得（降順）
            results = self.redis.zrevrange(ranking_key, 0, limit - 1, withscores=True)
            
            return [
                {
                    'countdown_id': countdown_id,
                    'trend_score': float(score)
                }
                for countdown_id, score in results
            ]
            
        except Exception as e:
            logger.error(f"Error getting ranking: {e}")
            return []
    
    def process_follow_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """フォロー/アンフォロー イベント処理"""
        try:
            user_id = event.get('userId')
            target_user_id = event.get('targetUserId')
            action = event.get('action')  # 'follow' or 'unfollow'
            
            if not all([user_id, target_user_id, action]):
                raise ValueError("Missing required fields: userId, targetUserId, action")
            
            pipe = self.redis.pipeline()
            
            if action == 'follow':
                # フォロー関係を追加
                pipe.sadd(USER_FOLLOWS_KEY.format(user_id=user_id), target_user_id)
                pipe.sadd(USER_FOLLOWERS_KEY.format(user_id=target_user_id), user_id)
                
                # カウンターを更新
                pipe.hincrby(FOLLOW_COUNT_KEY.format(user_id=user_id), 'following', 1)
                pipe.hincrby(FOLLOW_COUNT_KEY.format(user_id=target_user_id), 'followers', 1)
                
                # フォローした瞬間に対象ユーザーの最新投稿をタイムラインに追加
                self._add_user_posts_to_timeline(user_id, target_user_id, limit=100)
                
            elif action == 'unfollow':
                # フォロー関係を削除
                pipe.srem(USER_FOLLOWS_KEY.format(user_id=user_id), target_user_id)
                pipe.srem(USER_FOLLOWERS_KEY.format(user_id=target_user_id), user_id)
                
                # カウンターを更新
                pipe.hincrby(FOLLOW_COUNT_KEY.format(user_id=user_id), 'following', -1)
                pipe.hincrby(FOLLOW_COUNT_KEY.format(user_id=target_user_id), 'followers', -1)
                
                # タイムラインから対象ユーザーの投稿を削除
                self._remove_user_posts_from_timeline(user_id, target_user_id)
            
            pipe.execute()
            
            return {
                'success': True,
                'action': action,
                'user_id': user_id,
                'target_user_id': target_user_id
            }
            
        except Exception as e:
            logger.error(f"Error processing follow event: {e}")
            return {'success': False, 'error': str(e)}
    
    def _add_user_posts_to_timeline(self, follower_id: str, target_user_id: str, limit: int = 100):
        """フォロー時に対象ユーザーの投稿をタイムラインに追加"""
        try:
            # Firestoreから対象ユーザーの最新投稿を取得
            posts = db.collection('counts').where('creatorId', '==', target_user_id).order_by('eventDate', direction=firestore.Query.DESCENDING).limit(limit).stream()
            
            timeline_data = {}
            for post in posts:
                post_data = post.to_dict()
                # イベント日時をスコアとして使用
                score = post_data.get('eventDate').timestamp() if post_data.get('eventDate') else 0
                timeline_data[post.id] = score
            
            if timeline_data:
                self.redis.zadd(TIMELINE_KEY.format(user_id=follower_id), timeline_data)
                
        except Exception as e:
            logger.error(f"Error adding user posts to timeline: {e}")
    
    def _remove_user_posts_from_timeline(self, follower_id: str, target_user_id: str):
        """アンフォロー時に対象ユーザーの投稿をタイムラインから削除"""
        try:
            # 対象ユーザーのすべての投稿を取得
            posts = db.collection('counts').where('creatorId', '==', target_user_id).stream()
            
            post_ids = [post.id for post in posts]
            
            if post_ids:
                self.redis.zrem(TIMELINE_KEY.format(user_id=follower_id), *post_ids)
                
        except Exception as e:
            logger.error(f"Error removing user posts from timeline: {e}")
    
    def fan_out_to_followers(self, user_id: str, countdown_id: str, score: float):
        """新しい投稿をフォロワーのタイムラインに配信"""
        try:
            # フォロワーリストを取得
            followers = self.redis.smembers(USER_FOLLOWERS_KEY.format(user_id=user_id))
            
            if not followers:
                return
            
            pipe = self.redis.pipeline()
            
            # 各フォロワーのタイムラインに追加
            for follower_id in followers:
                pipe.zadd(TIMELINE_KEY.format(user_id=follower_id), {countdown_id: score})
                # タイムライン長制限（最新1000件）
                pipe.zremrangebyrank(TIMELINE_KEY.format(user_id=follower_id), 0, -1001)
            
            # グローバルタイムラインにも追加
            pipe.zadd(GLOBAL_TIMELINE_KEY, {countdown_id: score})
            pipe.zremrangebyrank(GLOBAL_TIMELINE_KEY, 0, -5001)  # 最新5000件
            
            pipe.execute()
            
            logger.info(f"Fanned out countdown {countdown_id} to {len(followers)} followers")
            
        except Exception as e:
            logger.error(f"Error in fan out: {e}")
    
    def get_user_timeline(self, user_id: str, limit: int = 50) -> list:
        """ユーザーのパーソナルタイムラインを取得"""
        try:
            # Redisからタイムラインを取得（スコア降順）
            timeline_ids = self.redis.zrevrange(TIMELINE_KEY.format(user_id=user_id), 0, limit - 1)
            
            if not timeline_ids:
                return []
            
            # Firestoreからカウントダウンデータを取得
            countdowns = []
            for countdown_id in timeline_ids:
                doc = db.collection('counts').document(countdown_id).get()
                if doc.exists:
                    data = doc.to_dict()
                    countdown_data = {
                        'id': doc.id,
                        'eventName': data.get('eventName', ''),
                        'description': data.get('description'),
                        'eventDate': data.get('eventDate').isoformat() if data.get('eventDate') else None,
                        'category': data.get('category', 'その他'),
                        'imageUrl': data.get('imageUrl'),
                        'creatorId': data.get('creatorId'),
                        'participantsCount': self.get_counter_value(doc.id, 'participants'),
                        'likesCount': self.get_counter_value(doc.id, 'likes'),
                        'commentsCount': self.get_counter_value(doc.id, 'comments'),
                        'viewsCount': self.get_counter_value(doc.id, 'views'),
                        'trendScore': self.get_trend_score(doc.id),
                    }
                    countdowns.append(countdown_data)
            
            return countdowns
            
        except Exception as e:
            logger.error(f"Error getting user timeline: {e}")
            return []
    
    def get_global_timeline(self, limit: int = 50) -> list:
        """グローバルタイムラインを取得"""
        try:
            # Redisからタイムラインを取得（スコア降順）
            timeline_ids = self.redis.zrevrange(GLOBAL_TIMELINE_KEY, 0, limit - 1)
            
            if not timeline_ids:
                return []
            
            # Firestoreからカウントダウンデータを取得
            countdowns = []
            for countdown_id in timeline_ids:
                doc = db.collection('counts').document(countdown_id).get()
                if doc.exists:
                    data = doc.to_dict()
                    countdown_data = {
                        'id': doc.id,
                        'eventName': data.get('eventName', ''),
                        'description': data.get('description'),
                        'eventDate': data.get('eventDate').isoformat() if data.get('eventDate') else None,
                        'category': data.get('category', 'その他'),
                        'imageUrl': data.get('imageUrl'),
                        'creatorId': data.get('creatorId'),
                        'participantsCount': self.get_counter_value(doc.id, 'participants'),
                        'likesCount': self.get_counter_value(doc.id, 'likes'),
                        'commentsCount': self.get_counter_value(doc.id, 'comments'),
                        'viewsCount': self.get_counter_value(doc.id, 'views'),
                        'trendScore': self.get_trend_score(doc.id),
                    }
                    countdowns.append(countdown_data)
            
            return countdowns
            
        except Exception as e:
            logger.error(f"Error getting global timeline: {e}")
            return []
    
    def get_follow_state(self, user_id: str, target_user_id: str) -> bool:
        """フォロー状態を取得"""
        try:
            return self.redis.sismember(USER_FOLLOWS_KEY.format(user_id=user_id), target_user_id)
        except Exception as e:
            logger.error(f"Error getting follow state: {e}")
            return False
    
    def get_follow_counts(self, user_id: str) -> Dict[str, int]:
        """フォロー数・フォロワー数を取得"""
        try:
            counts = self.redis.hgetall(FOLLOW_COUNT_KEY.format(user_id=user_id))
            return {
                'following': int(counts.get('following', 0)),
                'followers': int(counts.get('followers', 0))
            }
        except Exception as e:
            logger.error(f"Error getting follow counts: {e}")
            return {'following': 0, 'followers': 0}


# グローバルプロセッサインスタンス
processor = AnalyticsProcessor()

# Firestoreクライアント
db = firestore.Client()


def require_admin_auth(required_role='moderator'):
    """
    管理者認証デコレータ
    
    Args:
        required_role: 必要な権限 ('moderator' or 'superadmin')
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                # Authorizationヘッダーからトークンを取得
                auth_header = request.headers.get('Authorization')
                if not auth_header or not auth_header.startswith('Bearer '):
                    logger.warning('Missing or invalid Authorization header')
                    return jsonify({'error': 'Unauthorized - Missing token'}), 401
                
                token = auth_header.split(' ')[1]
                
                # IDトークンを検証
                decoded_token = auth.verify_id_token(token)
                user_id = decoded_token['uid']
                
                # カスタムクレームからロールを取得
                user_role = decoded_token.get('role')
                
                # 権限チェック
                if not user_role:
                    logger.warning(f'User {user_id} has no role assigned')
                    return jsonify({'error': 'Forbidden - No role assigned'}), 403
                
                if required_role == 'superadmin' and user_role != 'superadmin':
                    logger.warning(f'User {user_id} with role {user_role} attempted superadmin operation')
                    return jsonify({'error': 'Forbidden - Insufficient privileges'}), 403
                
                if user_role not in ['moderator', 'superadmin']:
                    logger.warning(f'User {user_id} with invalid role {user_role} attempted admin operation')
                    return jsonify({'error': 'Forbidden - Invalid role'}), 403
                
                # リクエストにユーザー情報を追加
                request.admin_user_id = user_id
                request.admin_user_role = user_role
                
                logger.info(f'Admin operation authorized for user {user_id} with role {user_role}')
                
                return f(*args, **kwargs)
                
            except auth.InvalidIdTokenError:
                logger.warning('Invalid ID token provided')
                return jsonify({'error': 'Unauthorized - Invalid token'}), 401
            except Exception as e:
                logger.error(f'Authentication error: {e}')
                return jsonify({'error': 'Authentication failed'}), 500
        
        return decorated_function
    return decorator


def log_admin_operation(operation: str, target_id: str, target_type: str, details: Dict[str, Any]):
    """
    管理者操作の監査ログを記録
    
    Args:
        operation: 操作種別 ('status_change', 'user_search', etc.)
        target_id: 対象ID
        target_type: 対象タイプ ('countdown', 'comment', 'user')
        details: 詳細情報
    """
    try:
        log_data = {
            'moderatorId': request.admin_user_id,
            'moderatorRole': request.admin_user_role,
            'operation': operation,
            'targetId': target_id,
            'targetType': target_type,
            'details': details,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'ipAddress': request.remote_addr,
            'userAgent': request.headers.get('User-Agent', '')
        }
        
        db.collection('moderation_logs').add(log_data)
        logger.info(f'Admin operation logged: {operation} on {target_type} {target_id} by {request.admin_user_id}')
        
    except Exception as e:
        logger.error(f'Failed to log admin operation: {e}')
        report_critical_error(e, 'admin_operation_logging_failed', {
            'operation': operation,
            'target_id': target_id,
            'target_type': target_type
        })


def report_critical_error(error: Exception, context: str, additional_data: Dict[str, Any] = None):
    """
    重大なエラーをError Reportingに報告し、アラートをトリガー
    
    Args:
        error: 発生した例外
        context: エラーのコンテキスト
        additional_data: 追加のデバッグ情報
    """
    try:
        # 重大度の高いエラーとしてログ出力
        logger.critical(f'CRITICAL ERROR in {context}: {error}', extra={
            'context': context,
            'additional_data': additional_data or {},
            'severity': 'CRITICAL'
        })
        
        # Error Reportingに送信
        error_client.report_exception(
            http_context=error_reporting.HTTPContext(
                method=request.method if request else 'UNKNOWN',
                url=request.url if request else 'UNKNOWN',
                user_agent=request.headers.get('User-Agent', '') if request else '',
                remote_ip=request.remote_addr if request else '',
            )
        )
        
    except Exception as report_error:
        # エラー報告の失敗は標準ログにのみ記録
        logger.error(f'Failed to report critical error: {report_error}')


def check_system_health():
    """
    システムヘルスチェックを実行し、問題があればアラート
    
    Returns:
        Dict: ヘルスチェック結果
    """
    health_status = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'status': 'healthy',
        'checks': {},
        'issues': []
    }
    
    # Redis接続チェック
    try:
        processor.redis.ping()
        health_status['checks']['redis'] = 'healthy'
    except Exception as e:
        health_status['status'] = 'unhealthy'
        health_status['checks']['redis'] = 'failed'
        health_status['issues'].append(f'Redis connection failed: {e}')
        report_critical_error(e, 'redis_health_check_failed')
    
    # Firestore接続チェック
    try:
        # 軽量なFirestoreクエリでヘルスチェック
        test_collection = db.collection('health_check').limit(1)
        list(test_collection.stream())
        health_status['checks']['firestore'] = 'healthy'
    except Exception as e:
        health_status['status'] = 'unhealthy'
        health_status['checks']['firestore'] = 'failed'
        health_status['issues'].append(f'Firestore connection failed: {e}')
        report_critical_error(e, 'firestore_health_check_failed')
    
    # メモリ使用量チェック（簡易版）
    try:
        import psutil
        memory_percent = psutil.virtual_memory().percent
        if memory_percent > 90:
            health_status['status'] = 'warning'
            health_status['issues'].append(f'High memory usage: {memory_percent}%')
            logger.warning(f'High memory usage detected: {memory_percent}%')
        health_status['checks']['memory'] = f'{memory_percent}%'
    except ImportError:
        health_status['checks']['memory'] = 'not_available'
    except Exception as e:
        health_status['checks']['memory'] = 'failed'
        logger.warning(f'Memory check failed: {e}')
    
    return health_status


@app.route('/process-events', methods=['POST'])
def process_events():
    """
    Pub/Sub からのイベント処理エンドポイント（統一パイプライン）
    
    Pub/Sub プッシュサブスクリプションからイベントを受信して統一処理
    """
    try:
        # Pub/Sub メッセージデコード
        envelope = request.get_json()
        if not envelope:
            logger.warning("No JSON data received")
            return jsonify({'error': 'No JSON data'}), 400
        
        pubsub_message = envelope.get('message')
        if not pubsub_message:
            logger.warning("No Pub/Sub message found")
            return jsonify({'error': 'No Pub/Sub message'}), 400
        
        # Base64デコード
        import base64
        data = base64.b64decode(pubsub_message.get('data', '')).decode('utf-8')
        event = json.loads(data)
        
        # 統一イベント処理
        result = processor.process_unified_event(event)
        
        # 成功レスポンス（Pub/Subへの確認応答）
        return jsonify(result), 200
        
    except Exception as e:
        logger.error(f"Error in unified event processing: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/events', methods=['POST'])
def direct_event():
    """
    クライアントからの直接イベント送信エンドポイント
    
    Flutter アプリから直接イベントを受信（高速パス）
    """
    try:
        event = request.get_json()
        if not event:
            return jsonify({'error': 'No JSON data'}), 400
        
        # 統一イベント処理
        result = processor.process_unified_event(event)
        
        return jsonify(result), 200
        
    except Exception as e:
        logger.error(f"Error in direct event processing: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/trend-score/<countdown_id>', methods=['GET'])
def get_trend_score(countdown_id: str):
    """トレンドスコア取得API"""
    try:
        score = processor.get_trend_score(countdown_id)
        return jsonify({
            'countdown_id': countdown_id,
            'trend_score': score,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting trend score: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/counter/<countdown_id>/<counter_type>', methods=['GET'])
def get_counter(countdown_id: str, counter_type: str):
    """カウンター値取得API"""
    try:
        count = processor.get_counter_value(countdown_id, counter_type)
        return jsonify({
            'countdown_id': countdown_id,
            'counter_type': counter_type,
            'count': count,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting counter: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/ranking', methods=['GET'])
def get_ranking():
    """ランキング取得API"""
    try:
        category = request.args.get('category')
        limit = int(request.args.get('limit', 20))
        
        ranking = processor.get_ranking(category, limit)
        
        return jsonify({
            'ranking': ranking,
            'category': category,
            'limit': limit,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting ranking: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/countdowns', methods=['GET'])
def get_countdowns():
    """カウントダウンリスト取得API"""
    try:
        # パラメータ取得
        category = request.args.get('category')
        limit = int(request.args.get('limit', 50))
        offset = int(request.args.get('offset', 0))
        
        # Firestore からカウントダウンを取得
        # 注意: この実装は移行期間中の一時的なもの
        # 将来的にはRedisキャッシュまたは別のデータストアを使用
        from google.cloud import firestore
        db = firestore.Client()
        
        query = db.collection('counts')
        
        if category:
            query = query.where('category', '==', category)
            
        query = query.order_by('eventDate', direction=firestore.Query.DESCENDING)
        query = query.limit(limit).offset(offset)
        
        docs = query.stream()
        
        countdowns = []
        for doc in docs:
            data = doc.to_dict()
            countdown_data = {
                'id': doc.id,
                'eventName': data.get('eventName', ''),
                'description': data.get('description'),
                'eventDate': data.get('eventDate').isoformat() if data.get('eventDate') else None,
                'category': data.get('category', 'その他'),
                'imageUrl': data.get('imageUrl'),
                'creatorId': data.get('creatorId'),
                # カウンターはRedisから取得
                'participantsCount': processor.get_counter_value(doc.id, 'participants'),
                'likesCount': processor.get_counter_value(doc.id, 'likes'),
                'commentsCount': processor.get_counter_value(doc.id, 'comments'),
                'viewsCount': processor.get_counter_value(doc.id, 'views'),
                'trendScore': processor.get_trend_score(doc.id),
            }
            countdowns.append(countdown_data)
        
        return jsonify({
            'countdowns': countdowns,
            'category': category,
            'limit': limit,
            'offset': offset,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting countdowns: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/user-state/<user_id>/<countdown_id>', methods=['GET'])
def get_user_state(user_id: str, countdown_id: str):
    """ユーザーの参加・いいね状態取得API"""
    try:
        # Redis から状態を取得
        participation_key = f"user_participation:{user_id}:{countdown_id}"
        like_key = f"user_like:{user_id}:{countdown_id}"
        
        is_participating = bool(processor.redis.get(participation_key))
        is_liked = bool(processor.redis.get(like_key))
        
        # フォロー状態も取得（countdown_idがユーザーIDとして扱われる場合）
        is_following = processor.get_follow_state(user_id, countdown_id)
        
        return jsonify({
            'user_id': user_id,
            'countdown_id': countdown_id,
            'is_participating': is_participating,
            'is_liked': is_liked,
            'is_following': is_following,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting user state: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/comments/<countdown_id>', methods=['GET'])
def get_comments(countdown_id: str):
    """コメントリスト取得API（ページネーション対応）"""
    try:
        limit = int(request.args.get('limit', 20))
        offset = int(request.args.get('offset', 0))
        
        # Firestore からコメントを取得
        from google.cloud import firestore
        db = firestore.Client()
        
        query = db.collection('comments')
        query = query.where('countdownId', '==', countdown_id)
        query = query.order_by('createdAt', direction=firestore.Query.DESCENDING)
        query = query.limit(limit).offset(offset)
        
        docs = query.stream()
        
        comments = []
        for doc in docs:
            data = doc.to_dict()
            comment_data = {
                'id': doc.id,
                'countdownId': data.get('countdownId'),
                'content': data.get('content'),
                'userId': data.get('userId'),
                'userName': data.get('userName'),
                'userAvatarUrl': data.get('userAvatarUrl'),
                'createdAt': data.get('createdAt').isoformat() if data.get('createdAt') else None,
                'likesCount': data.get('likesCount', 0),
            }
            comments.append(comment_data)
        
        return jsonify({
            'comments': comments,
            'countdown_id': countdown_id,
            'limit': limit,
            'offset': offset,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting comments: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/admin/contents/moderate', methods=['POST'])
@require_admin_auth('moderator')
def moderate_content():
    """
    コンテンツモデレーションAPI
    
    コンテンツのステータスを変更し、監査ログを記録
    """
    try:
        data = request.get_json()
        
        # 必須フィールドの検証
        required_fields = ['contentId', 'contentType', 'newStatus', 'reason']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        content_id = data['contentId']
        content_type = data['contentType']  # 'countdown' or 'comment'
        new_status = data['newStatus']
        reason = data['reason']
        notes = data.get('notes', '')
        
        # ステータスの検証
        valid_statuses = ['visible', 'hidden_by_moderator', 'deleted_by_user']
        if new_status not in valid_statuses:
            return jsonify({'error': f'Invalid status. Must be one of: {valid_statuses}'}), 400
        
        # コンテンツタイプの検証
        if content_type not in ['countdown', 'comment']:
            return jsonify({'error': 'Invalid content type. Must be countdown or comment'}), 400
        
        # Firestoreコレクション名を決定
        collection_name = 'counts' if content_type == 'countdown' else 'comments'
        
        # コンテンツの取得と更新
        doc_ref = db.collection(collection_name).document(content_id)
        doc = doc_ref.get()
        
        if not doc.exists:
            return jsonify({'error': f'{content_type.capitalize()} not found'}), 404
        
        # 現在のデータを取得（監査ログ用）
        current_data = doc.to_dict()
        old_status = current_data.get('status', 'visible')
        
        # モデレーション情報を作成
        moderation_info = {
            'moderatorId': request.admin_user_id,
            'moderatedAt': firestore.SERVER_TIMESTAMP,
            'reason': reason,
            'notes': notes,
            'oldStatus': old_status
        }
        
        # ドキュメントを更新
        update_data = {
            'status': new_status,
            'moderationInfo': moderation_info
        }
        
        doc_ref.update(update_data)
        
        # 監査ログを記録
        log_admin_operation(
            operation='status_change',
            target_id=content_id,
            target_type=content_type,
            details={
                'oldStatus': old_status,
                'newStatus': new_status,
                'reason': reason,
                'notes': notes
            }
        )
        
        logger.info(f'Content {content_id} status changed from {old_status} to {new_status} by {request.admin_user_id}')
        
        return jsonify({
            'success': True,
            'contentId': content_id,
            'contentType': content_type,
            'oldStatus': old_status,
            'newStatus': new_status,
            'moderatorId': request.admin_user_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f'Error in content moderation: {e}')
        return jsonify({'error': str(e)}), 500


@app.route('/admin/users/search', methods=['GET'])
@require_admin_auth('moderator')
def search_users():
    """
    ユーザー検索API
    
    ユーザーIDや名前でユーザーを検索
    """
    try:
        query = request.args.get('q', '').strip()
        limit = int(request.args.get('limit', 20))
        
        if not query:
            return jsonify({'error': 'Search query is required'}), 400
        
        if limit > 100:
            limit = 100  # 上限を設定
        
        # Firebase Authからユーザーを検索
        users = []
        try:
            # UIDで検索を試行
            user_record = auth.get_user(query)
            users.append({
                'uid': user_record.uid,
                'email': user_record.email,
                'displayName': user_record.display_name,
                'disabled': user_record.disabled,
                'emailVerified': user_record.email_verified,
                'creationTime': user_record.user_metadata.creation_timestamp.isoformat() if user_record.user_metadata.creation_timestamp else None,
                'lastSignInTime': user_record.user_metadata.last_sign_in_timestamp.isoformat() if user_record.user_metadata.last_sign_in_timestamp else None
            })
        except auth.UserNotFoundError:
            # UIDで見つからない場合はメールで検索
            try:
                user_record = auth.get_user_by_email(query)
                users.append({
                    'uid': user_record.uid,
                    'email': user_record.email,
                    'displayName': user_record.display_name,
                    'disabled': user_record.disabled,
                    'emailVerified': user_record.email_verified,
                    'creationTime': user_record.user_metadata.creation_timestamp.isoformat() if user_record.user_metadata.creation_timestamp else None,
                    'lastSignInTime': user_record.user_metadata.last_sign_in_timestamp.isoformat() if user_record.user_metadata.last_sign_in_timestamp else None
                })
            except auth.UserNotFoundError:
                pass
        
        # 監査ログを記録
        log_admin_operation(
            operation='user_search',
            target_id=query,
            target_type='user',
            details={
                'searchQuery': query,
                'resultsCount': len(users)
            }
        )
        
        return jsonify({
            'users': users,
            'searchQuery': query,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f'Error in user search: {e}')
        return jsonify({'error': str(e)}), 500


@app.route('/admin/contents/reported', methods=['GET'])
@require_admin_auth('moderator')
def get_reported_contents():
    """
    通報されたコンテンツ一覧取得API
    
    ユーザーからの通報があるコンテンツを取得
    """
    try:
        limit = int(request.args.get('limit', 50))
        status_filter = request.args.get('status', 'pending')  # pending, reviewed, resolved
        
        if limit > 100:
            limit = 100
        
        # reportsコレクションから通報を取得
        query = db.collection('reports')
        
        if status_filter != 'all':
            query = query.where('status', '==', status_filter)
        
        query = query.order_by('createdAt', direction=firestore.Query.DESCENDING)
        query = query.limit(limit)
        
        docs = query.stream()
        
        reports = []
        for doc in docs:
            data = doc.to_dict()
            report_data = {
                'id': doc.id,
                'contentId': data.get('contentId'),
                'contentType': data.get('contentType'),
                'reportedBy': data.get('reportedBy'),
                'reason': data.get('reason'),
                'description': data.get('description', ''),
                'status': data.get('status', 'pending'),
                'createdAt': data.get('createdAt').isoformat() if data.get('createdAt') else None,
                'reviewedBy': data.get('reviewedBy'),
                'reviewedAt': data.get('reviewedAt').isoformat() if data.get('reviewedAt') else None
            }
            reports.append(report_data)
        
        # 監査ログを記録
        log_admin_operation(
            operation='view_reports',
            target_id='reports_list',
            target_type='reports',
            details={
                'statusFilter': status_filter,
                'limit': limit,
                'resultsCount': len(reports)
            }
        )
        
        return jsonify({
            'reports': reports,
            'statusFilter': status_filter,
            'limit': limit,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f'Error getting reported contents: {e}')
        return jsonify({'error': str(e)}), 500


@app.route('/follow-user', methods=['POST'])
def follow_user():
    """フォロー/アンフォローAPI"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data'}), 400
        
        user_id = data.get('userId')
        target_user_id = data.get('targetUserId')
        action = data.get('action', 'follow')  # 'follow' or 'unfollow'
        
        if not all([user_id, target_user_id]):
            return jsonify({'error': 'Missing userId or targetUserId'}), 400
        
        # フォローイベントを処理
        follow_event = {
            'userId': user_id,
            'targetUserId': target_user_id,
            'action': action
        }
        
        result = processor.process_follow_event(follow_event)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Error in follow user: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/user-follows/<user_id>', methods=['GET'])
def get_user_follows(user_id: str):
    """ユーザーのフォロー状態取得API"""
    try:
        target_user_id = request.args.get('targetUserId')
        
        if target_user_id:
            # 特定のユーザーに対するフォロー状態を取得
            is_following = processor.get_follow_state(user_id, target_user_id)
            return jsonify({
                'user_id': user_id,
                'target_user_id': target_user_id,
                'is_following': is_following,
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        else:
            # フォロー数・フォロワー数を取得
            counts = processor.get_follow_counts(user_id)
            return jsonify({
                'user_id': user_id,
                'follow_counts': counts,
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        
    except Exception as e:
        logger.error(f"Error getting user follows: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/followers/<user_id>', methods=['GET'])
def get_followers(user_id: str):
    """フォロワー取得API"""
    try:
        followers = processor.redis.smembers(USER_FOLLOWERS_KEY.format(user_id=user_id))
        return jsonify({
            'user_id': user_id,
            'followers': list(followers),
            'count': len(followers),
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting followers: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/timeline/<user_id>', methods=['GET'])
def get_user_timeline(user_id: str):
    """パーソナルタイムライン取得API"""
    try:
        limit = int(request.args.get('limit', 50))
        timeline = processor.get_user_timeline(user_id, limit)
        
        return jsonify({
            'user_id': user_id,
            'countdowns': timeline,
            'limit': limit,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting user timeline: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/global-timeline', methods=['GET'])
def get_global_timeline():
    """グローバルタイムライン取得API"""
    try:
        limit = int(request.args.get('limit', 50))
        timeline = processor.get_global_timeline(limit)
        
        return jsonify({
            'countdowns': timeline,
            'limit': limit,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting global timeline: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/health', methods=['GET'])
def health_check():
    """拡張ヘルスチェック"""
    try:
        health_status = check_system_health()
        
        # ステータスに応じてHTTPコードを決定
        if health_status['status'] == 'healthy':
            return jsonify(health_status), 200
        elif health_status['status'] == 'warning':
            return jsonify(health_status), 200  # 警告レベルは200で返す
        else:
            return jsonify(health_status), 503  # Service Unavailable
            
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        report_critical_error(e, 'health_check_endpoint_failed')
        
        return jsonify({
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'version': '1.2'
        }), 500


@app.route('/health/detailed', methods=['GET'])
def detailed_health_check():
    """詳細ヘルスチェック（管理者用）"""
    try:
        health_status = check_system_health()
        
        # 追加の詳細情報を含める
        health_status['service_info'] = {
            'version': '1.2',
            'uptime_check': 'ok',
            'environment': os.environ.get('ENVIRONMENT', 'unknown'),
        }
        
        # Redis詳細情報
        try:
            redis_info = processor.redis.info()
            health_status['redis_details'] = {
                'version': redis_info.get('redis_version'),
                'connected_clients': redis_info.get('connected_clients'),
                'used_memory_human': redis_info.get('used_memory_human'),
            }
        except Exception as e:
            health_status['redis_details'] = {'error': str(e)}
        
        return jsonify(health_status)
        
    except Exception as e:
        logger.error(f"Detailed health check failed: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)