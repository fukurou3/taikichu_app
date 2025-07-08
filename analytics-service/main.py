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
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional
from functools import wraps
from collections import defaultdict
import hashlib
import uuid

import redis
from flask import Flask, request, jsonify, g
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

# Firestore クライアント
firestore_client = firestore.Client()

app = Flask(__name__)

# レートリミット用のメモリストレージ（本番環境ではRedisを使用）
rate_limit_storage = defaultdict(list)
failed_attempts_storage = defaultdict(int)

# 監査ログ設定
AUDIT_LOG_COLLECTION = 'moderation_logs'
SECURITY_LOG_COLLECTION = 'security_logs'

# 管理者権限レベル
ADMIN_LEVELS = {
    'viewer': 1,
    'moderator': 2, 
    'admin': 3,
    'superadmin': 4
}

# 操作に必要な権限レベル
REQUIRED_PERMISSIONS = {
    'view_reports': 1,
    'view_audit_logs': 1,
    'view_users': 1,
    'moderate_content': 2,
    'hide_content': 2,
    'warn_user': 2,
    'resolve_report': 2,
    'ban_user': 3,
    'delete_content': 3,
    'delete_user': 3,
    'mass_action': 3,
    'manage_admins': 4,
    'system_settings': 4,
}

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

# 🛡️ セキュリティと監査ログ機能

def create_audit_log(
    action: str,
    target_type: str, 
    target_id: str,
    reason: str,
    admin_uid: str,
    admin_email: str = None,
    notes: str = None,
    metadata: Dict[str, Any] = None,
    previous_state: str = None,
    new_state: str = None,
    ip_address: str = None,
    user_agent: str = None
) -> str:
    """
    🛡️ 監査ログの作成（バックエンド主導）
    
    全ての管理者操作を確実に記録し、改ざん不可能な監査証跡を作成
    """
    try:
        log_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc)
        
        # 重要度判定
        severity = calculate_severity(action)
        requires_approval = check_requires_approval(action)
        
        # 操作のハッシュ値生成（改ざん検証用）
        operation_hash = hashlib.sha256(
            f"{admin_uid}:{action}:{target_type}:{target_id}:{timestamp.isoformat()}".encode()
        ).hexdigest()
        
        audit_data = {
            'log_id': log_id,
            'action': action,
            'target_type': target_type,
            'target_id': target_id,
            'reason': reason,
            'admin_uid': admin_uid,
            'admin_email': admin_email,
            'timestamp': timestamp,
            'ip_address': ip_address,
            'user_agent': user_agent,
            'notes': notes,
            'metadata': metadata or {},
            'previous_state': previous_state,
            'new_state': new_state,
            'severity': severity,
            'requires_approval': requires_approval,
            'operation_hash': operation_hash,
            'created_at': firestore.SERVER_TIMESTAMP
        }
        
        # Firestoreに確実に保存
        doc_ref = firestore_client.collection(AUDIT_LOG_COLLECTION).document(log_id)
        doc_ref.set(audit_data)
        
        # Redisにも高速検索用にキャッシュ
        redis_conn = redis.Redis(connection_pool=redis_client)
        redis_key = f"audit_log:{log_id}"
        redis_conn.setex(redis_key, 86400, json.dumps(audit_data, default=str))  # 24時間キャッシュ
        
        logger.info(f"Audit log created: {log_id} for action {action} by {admin_uid}")
        
        return log_id
        
    except Exception as e:
        logger.error(f"Failed to create audit log: {e}")
        # 監査ログの記録失敗は重大なエラー
        error_client.report_exception()
        raise Exception(f"監査ログの記録に失敗しました: {e}")

def calculate_severity(action: str) -> str:
    """操作の重要度を計算"""
    high_risk = ['ban_user', 'delete_user', 'delete_content', 'mass_action', 'manage_admins']
    medium_risk = ['hide_content', 'moderate_content', 'warn_user', 'resolve_report']
    
    if action in high_risk:
        return 'HIGH'
    elif action in medium_risk:
        return 'MEDIUM'
    else:
        return 'LOW'

def check_requires_approval(action: str) -> bool:
    """承認が必要な操作かチェック"""
    approval_required = ['ban_user', 'delete_user', 'delete_content', 'mass_action']
    return action in approval_required

def create_security_log(
    event_type: str,
    severity: str,
    description: str,
    user_uid: str = None,
    ip_address: str = None,
    metadata: Dict[str, Any] = None
) -> str:
    """
    🚨 セキュリティログの作成
    
    不正アクセス試行、権限昇格攻撃、異常な操作パターンを記録
    """
    try:
        log_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc)
        
        security_data = {
            'log_id': log_id,
            'event_type': event_type,
            'severity': severity,
            'description': description,
            'user_uid': user_uid,
            'ip_address': ip_address,
            'timestamp': timestamp,
            'metadata': metadata or {},
            'created_at': firestore.SERVER_TIMESTAMP
        }
        
        # 重大なセキュリティイベントは即座に保存
        doc_ref = firestore_client.collection(SECURITY_LOG_COLLECTION).document(log_id)
        doc_ref.set(security_data)
        
        # 高重要度の場合はアラート
        if severity in ['HIGH', 'CRITICAL']:
            logger.warning(f"SECURITY ALERT: {event_type} - {description}")
            # 実際の実装では、ここでSlack/Emailアラートを送信
        
        return log_id
        
    except Exception as e:
        logger.error(f"Failed to create security log: {e}")
        error_client.report_exception()
        return None

def check_rate_limit(user_id: str, action: str, limit: int = 10, window_seconds: int = 60) -> bool:
    """
    🛡️ レートリミットチェック
    
    指定時間内の操作回数を制限して総当たり攻撃を防止
    """
    now = time.time()
    key = f"{user_id}:{action}"
    
    # 古いエントリを削除
    rate_limit_storage[key] = [
        timestamp for timestamp in rate_limit_storage[key] 
        if now - timestamp < window_seconds
    ]
    
    # 制限チェック
    if len(rate_limit_storage[key]) >= limit:
        # レートリミット違反をセキュリティログに記録
        create_security_log(
            event_type='rate_limit_exceeded',
            severity='MEDIUM',
            description=f'Rate limit exceeded for {action}',
            user_uid=user_id,
            ip_address=request.environ.get('REMOTE_ADDR'),
            metadata={
                'action': action,
                'attempts': len(rate_limit_storage[key]),
                'limit': limit,
                'window_seconds': window_seconds
            }
        )
        return False
    
    # 操作を記録
    rate_limit_storage[key].append(now)
    return True

def check_failed_attempts(user_id: str, max_attempts: int = 5) -> bool:
    """
    🚨 失敗試行回数チェック
    
    連続した認証失敗を監視して不正アクセスを検出
    """
    if failed_attempts_storage[user_id] >= max_attempts:
        create_security_log(
            event_type='account_locked',
            severity='HIGH',
            description=f'Account locked due to {failed_attempts_storage[user_id]} failed attempts',
            user_uid=user_id,
            ip_address=request.environ.get('REMOTE_ADDR')
        )
        return False
    return True

def record_failed_attempt(user_id: str):
    """認証失敗を記録"""
    failed_attempts_storage[user_id] += 1
    
    create_security_log(
        event_type='authentication_failed',
        severity='MEDIUM',
        description=f'Authentication failed (attempt {failed_attempts_storage[user_id]})',
        user_uid=user_id,
        ip_address=request.environ.get('REMOTE_ADDR')
    )

def reset_failed_attempts(user_id: str):
    """認証成功時に失敗カウントをリセット"""
    if user_id in failed_attempts_storage:
        del failed_attempts_storage[user_id]

def require_admin_auth(required_action: str = None):
    """
    🛡️ 強化された管理者認証デコレーター
    
    認証・認可・レートリミット・監査ログを統合
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                # 1. IP ベースのレートリミット
                client_ip = request.environ.get('REMOTE_ADDR', 'unknown')
                if not check_rate_limit(f"ip:{client_ip}", 'admin_api', limit=30, window_seconds=60):
                    return jsonify({
                        'error': 'Rate limit exceeded',
                        'retry_after': 60
                    }), 429
                
                # 2. Authorization ヘッダーチェック
                auth_header = request.headers.get('Authorization')
                if not auth_header or not auth_header.startswith('Bearer '):
                    create_security_log(
                        event_type='unauthorized_access_attempt',
                        severity='MEDIUM',
                        description='Missing or invalid Authorization header',
                        ip_address=client_ip
                    )
                    return jsonify({'error': 'Unauthorized'}), 401
                
                # 3. Firebase ID Token 検証
                token = auth_header.split('Bearer ')[1]
                try:
                    decoded_token = auth.verify_id_token(token)
                    user_uid = decoded_token['uid']
                    user_email = decoded_token.get('email')
                    user_role = decoded_token.get('role')
                except Exception as e:
                    record_failed_attempt(f"ip:{client_ip}")
                    create_security_log(
                        event_type='invalid_token',
                        severity='HIGH',
                        description=f'Invalid Firebase token: {str(e)}',
                        ip_address=client_ip
                    )
                    return jsonify({'error': 'Invalid token'}), 401
                
                # 4. 失敗試行回数チェック
                if not check_failed_attempts(user_uid):
                    return jsonify({'error': 'Account temporarily locked'}), 423
                
                # 5. 管理者権限チェック
                if not user_role or user_role not in ADMIN_LEVELS:
                    create_security_log(
                        event_type='unauthorized_admin_access',
                        severity='HIGH',
                        description='Non-admin user attempted admin operation',
                        user_uid=user_uid,
                        ip_address=client_ip,
                        metadata={'user_role': user_role}
                    )
                    return jsonify({'error': 'Admin privileges required'}), 403
                
                # 6. 特定操作の権限チェック
                if required_action:
                    user_level = ADMIN_LEVELS.get(user_role, 0)
                    required_level = REQUIRED_PERMISSIONS.get(required_action, 999)
                    
                    if user_level < required_level:
                        create_security_log(
                            event_type='insufficient_permissions',
                            severity='HIGH',
                            description=f'Insufficient permissions for {required_action}',
                            user_uid=user_uid,
                            ip_address=client_ip,
                            metadata={
                                'user_role': user_role,
                                'user_level': user_level,
                                'required_action': required_action,
                                'required_level': required_level
                            }
                        )
                        return jsonify({
                            'error': 'Insufficient permissions',
                            'required_action': required_action
                        }), 403
                
                # 7. 営業時間チェック（高リスク操作のみ）
                high_risk_actions = ['ban_user', 'delete_user', 'delete_content', 'mass_action']
                if required_action in high_risk_actions:
                    current_hour = datetime.now().hour
                    if current_hour < 6 or current_hour > 22:
                        create_security_log(
                            event_type='business_hours_violation',
                            severity='MEDIUM',
                            description=f'High-risk operation {required_action} attempted outside business hours',
                            user_uid=user_uid,
                            ip_address=client_ip
                        )
                        return jsonify({
                            'error': 'High-risk operations only allowed during business hours (6:00-22:00)'
                        }), 403
                
                # 8. 認証成功時の処理
                reset_failed_attempts(user_uid)
                
                # 9. リクエスト情報をグローバル変数に設定
                g.admin_uid = user_uid
                g.admin_email = user_email
                g.admin_role = user_role
                g.client_ip = client_ip
                g.user_agent = request.headers.get('User-Agent', 'unknown')
                
                # 10. API アクセスログを記録
                create_audit_log(
                    action=f'api_access_{required_action or f.name}',
                    target_type='api',
                    target_id=request.endpoint or f.name,
                    reason='API access',
                    admin_uid=user_uid,
                    admin_email=user_email,
                    ip_address=client_ip,
                    user_agent=g.user_agent,
                    metadata={
                        'method': request.method,
                        'path': request.path,
                        'query_params': dict(request.args),
                        'user_role': user_role
                    }
                )
                
                return f(*args, **kwargs)
                
            except Exception as e:
                logger.error(f"Admin auth error: {e}")
                error_client.report_exception()
                return jsonify({
                    'error': 'Authentication system error',
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }), 500
        
        return decorated_function
    return decorator


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


# 🛡️ セキュリティ強化された管理者APIエンドポイント

@app.route('/admin/contents/moderate', methods=['POST'])
@require_admin_auth('moderate_content')
def moderate_content():
    """
    🛡️ コンテンツモデレーション（バックエンド主導の監査ログ）
    """
    try:
        data = request.get_json()
        content_id = data.get('contentId')
        content_type = data.get('contentType')
        new_status = data.get('newStatus')
        reason = data.get('reason')
        notes = data.get('notes')
        
        if not all([content_id, content_type, new_status, reason]):
            return jsonify({'error': 'Missing required fields'}), 400
        
        # 現在の状態を取得
        if content_type == 'countdown':
            doc_ref = firestore_client.collection('counts').document(content_id)
        elif content_type == 'comment':
            doc_ref = firestore_client.collection('comments').document(content_id)
        else:
            return jsonify({'error': 'Invalid content type'}), 400
        
        doc = doc_ref.get()
        if not doc.exists:
            return jsonify({'error': 'Content not found'}), 404
        
        previous_state = doc.to_dict().get('status', 'unknown')
        
        # 🛡️ バックエンドで監査ログを記録（操作前）
        log_id = create_audit_log(
            action='moderate_content',
            target_type=content_type,
            target_id=content_id,
            reason=reason,
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            notes=notes,
            previous_state=previous_state,
            new_state=new_status,
            ip_address=g.client_ip,
            user_agent=g.user_agent,
            metadata={
                'moderation_type': 'content_status_change',
                'action_source': 'admin_api'
            }
        )
        
        # コンテンツの状態を更新
        doc_ref.update({
            'status': new_status,
            'moderated_at': firestore.SERVER_TIMESTAMP,
            'moderated_by': g.admin_uid,
            'moderation_reason': reason
        })
        
        # 成功ログを記録
        create_audit_log(
            action='moderate_content_completed',
            target_type=content_type,
            target_id=content_id,
            reason='Moderation completed successfully',
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            metadata={
                'original_log_id': log_id,
                'operation_result': 'success'
            }
        )
        
        return jsonify({
            'success': True,
            'audit_log_id': log_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"Content moderation failed: {e}")
        # 失敗ログを記録
        create_audit_log(
            action='moderate_content_failed',
            target_type=data.get('contentType', 'unknown'),
            target_id=data.get('contentId', 'unknown'),
            reason=f'Operation failed: {str(e)}',
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            metadata={'error': str(e)}
        )
        return jsonify({'error': 'Moderation failed'}), 500

@app.route('/admin/users/ban', methods=['POST'])
@require_admin_auth('ban_user')
def ban_user():
    """
    🛡️ ユーザーBAN（高リスク操作・完全監査）
    """
    try:
        data = request.get_json()
        user_id = data.get('userId')
        reason = data.get('reason')
        notes = data.get('notes')
        duration_days = data.get('durationDays')
        
        if not all([user_id, reason]):
            return jsonify({'error': 'Missing required fields'}), 400
        
        # ユーザー情報を取得
        try:
            user_record = auth.get_user(user_id)
            previous_state = f"disabled: {user_record.disabled}"
        except auth.UserNotFoundError:
            return jsonify({'error': 'User not found'}), 404
        
        # 🛡️ 高リスク操作の監査ログ記録
        log_id = create_audit_log(
            action='ban_user',
            target_type='user',
            target_id=user_id,
            reason=reason,
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            notes=notes,
            previous_state=previous_state,
            new_state=f"banned for {duration_days} days" if duration_days else "permanently banned",
            ip_address=g.client_ip,
            user_agent=g.user_agent,
            metadata={
                'ban_duration_days': duration_days,
                'severity': 'HIGH',
                'requires_approval': True
            }
        )
        
        # ユーザーアカウントを無効化
        auth.update_user(user_id, disabled=True)
        
        # BANレコードをFirestoreに保存
        ban_data = {
            'user_id': user_id,
            'banned_by': g.admin_uid,
            'reason': reason,
            'notes': notes,
            'banned_at': firestore.SERVER_TIMESTAMP,
            'duration_days': duration_days,
            'audit_log_id': log_id
        }
        
        if duration_days:
            ban_data['expires_at'] = datetime.now(timezone.utc) + timedelta(days=duration_days)
        
        firestore_client.collection('user_bans').document(user_id).set(ban_data)
        
        # 成功ログを記録
        create_audit_log(
            action='ban_user_completed',
            target_type='user',
            target_id=user_id,
            reason='User ban completed successfully',
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            metadata={
                'original_log_id': log_id,
                'operation_result': 'success'
            }
        )
        
        return jsonify({
            'success': True,
            'audit_log_id': log_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"User ban failed: {e}")
        create_audit_log(
            action='ban_user_failed',
            target_type='user',
            target_id=data.get('userId', 'unknown'),
            reason=f'Ban operation failed: {str(e)}',
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            metadata={'error': str(e)}
        )
        return jsonify({'error': 'Ban operation failed'}), 500

@app.route('/admin/logs', methods=['GET'])
@require_admin_auth('view_audit_logs')
def get_audit_logs():
    """
    🛡️ 監査ログ取得（フィルタリング・ページネーション対応）
    """
    try:
        # フィルターパラメータ
        admin_uid = request.args.get('admin_uid')
        target_type = request.args.get('target_type')
        target_id = request.args.get('target_id')
        action = request.args.get('action')
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        limit = min(int(request.args.get('limit', 50)), 100)  # 最大100件
        last_document_id = request.args.get('last_document_id')
        
        # アクセスログを記録
        create_audit_log(
            action='view_audit_logs',
            target_type='audit_system',
            target_id='log_query',
            reason='Audit log access',
            admin_uid=g.admin_uid,
            admin_email=g.admin_email,
            metadata={
                'query_filters': {
                    'admin_uid': admin_uid,
                    'target_type': target_type,
                    'action': action,
                    'limit': limit
                }
            }
        )
        
        # Firestoreクエリを構築
        query = firestore_client.collection(AUDIT_LOG_COLLECTION)
        
        # フィルター適用
        if admin_uid:
            query = query.where('admin_uid', '==', admin_uid)
        if target_type:
            query = query.where('target_type', '==', target_type)
        if action:
            query = query.where('action', '==', action)
        if start_date:
            start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            query = query.where('timestamp', '>=', start_dt)
        if end_date:
            end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
            query = query.where('timestamp', '<=', end_dt)
        
        # ページネーション
        if last_document_id:
            last_doc = firestore_client.collection(AUDIT_LOG_COLLECTION).document(last_document_id).get()
            if last_doc.exists:
                query = query.start_after(last_doc)
        
        # 実行
        query = query.order_by('timestamp', direction=firestore.Query.DESCENDING).limit(limit)
        docs = query.stream()
        
        logs = []
        for doc in docs:
            log_data = doc.to_dict()
            log_data['id'] = doc.id
            # Timestampを文字列に変換
            if 'timestamp' in log_data:
                log_data['timestamp'] = log_data['timestamp'].isoformat()
            logs.append(log_data)
        
        return jsonify({
            'success': True,
            'logs': logs,
            'count': len(logs),
            'has_more': len(logs) == limit
        })
        
    except Exception as e:
        logger.error(f"Audit log retrieval failed: {e}")
        return jsonify({'error': 'Failed to retrieve audit logs'}), 500

@app.route('/admin/activity-stats', methods=['GET'])
@require_admin_auth('view_audit_logs')
def get_admin_activity_stats():
    """
    📊 管理者活動統計取得
    """
    try:
        # 期間パラメータ
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        admin_uid = request.args.get('admin_uid')
        
        # デフォルトは過去30日
        if not end_date:
            end_date = datetime.now(timezone.utc)
        else:
            end_date = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
        
        if not start_date:
            start_date = end_date - timedelta(days=30)
        else:
            start_date = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
        
        # 統計クエリ
        query = firestore_client.collection(AUDIT_LOG_COLLECTION).where(
            'timestamp', '>=', start_date
        ).where(
            'timestamp', '<=', end_date
        )
        
        if admin_uid:
            query = query.where('admin_uid', '==', admin_uid)
        
        docs = list(query.stream())
        
        # 統計計算
        stats = {
            'total_actions': len(docs),
            'high_risk_actions': 0,
            'user_bans': 0,
            'content_deletions': 0,
            'actions_by_admin': {},
            'actions_by_type': {},
            'recent_actions': []
        }
        
        for doc in docs:
            data = doc.to_dict()
            action = data.get('action', 'unknown')
            admin_email = data.get('admin_email', 'unknown')
            severity = data.get('severity', 'LOW')
            
            # 統計集計
            if severity == 'HIGH':
                stats['high_risk_actions'] += 1
            if 'ban_user' in action:
                stats['user_bans'] += 1
            if 'delete_content' in action:
                stats['content_deletions'] += 1
            
            # 管理者別集計
            if admin_email not in stats['actions_by_admin']:
                stats['actions_by_admin'][admin_email] = 0
            stats['actions_by_admin'][admin_email] += 1
            
            # アクション別集計
            if action not in stats['actions_by_type']:
                stats['actions_by_type'][action] = 0
            stats['actions_by_type'][action] += 1
        
        # トップ管理者（上位5名）
        top_moderators = sorted(
            stats['actions_by_admin'].items(),
            key=lambda x: x[1],
            reverse=True
        )[:5]
        
        stats['top_moderators'] = [
            {'admin_email': email, 'action_count': count}
            for email, count in top_moderators
        ]
        
        # 最近のアクション（上位10件）
        recent_docs = sorted(docs, key=lambda x: x.to_dict().get('timestamp', datetime.min), reverse=True)[:10]
        stats['recent_actions'] = [
            {
                'action': doc.to_dict().get('action'),
                'target_type': doc.to_dict().get('target_type'),
                'target_id': doc.to_dict().get('target_id'),
                'timestamp': doc.to_dict().get('timestamp').isoformat() if doc.to_dict().get('timestamp') else None,
                'severity': doc.to_dict().get('severity')
            }
            for doc in recent_docs
        ]
        
        return jsonify({
            'success': True,
            'stats': stats,
            'period': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat()
            }
        })
        
    except Exception as e:
        logger.error(f"Admin activity stats failed: {e}")
        return jsonify({'error': 'Failed to retrieve activity stats'}), 500


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