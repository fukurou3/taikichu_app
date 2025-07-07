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

import redis
from flask import Flask, request, jsonify
from google.cloud import logging as cloud_logging

# Cloud Logging設定
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

app = Flask(__name__)

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
            
            # 5. 活動メタデータ更新
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
            
            # 6. 時間別集計（オプション）
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


# グローバルプロセッサインスタンス
processor = AnalyticsProcessor()


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


@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    try:
        # Redis接続確認
        processor.redis.ping()
        
        return jsonify({
            'status': 'healthy',
            'redis': 'connected',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'version': '1.0'
        })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)