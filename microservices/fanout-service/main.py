"""
ファンアウト専用マイクロサービス
責任: フォロワーのタイムライン更新のみ

Pub/Sub → このサービス → Redis (タイムライン更新)
他の機能とは完全に分離、独立してスケール・障害処理
"""

import json
import logging
import os
import redis
from datetime import datetime
from google.cloud import firestore
from google.cloud import pubsub_v1
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Redis接続
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', 6379)),
    decode_responses=True
)

# Firestore接続
firestore_client = firestore.Client()

@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    try:
        # Redis接続確認
        redis_client.ping()
        return jsonify({
            'status': 'healthy',
            'service': 'fanout-service',
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e)
        }), 500

@app.route('/process-event', methods=['POST'])
def process_fanout_event():
    """
    Pub/Subからのイベント処理
    投稿作成時のファンアウト処理のみ
    """
    try:
        # Pub/Subメッセージのデコード
        envelope = request.get_json()
        if not envelope:
            return jsonify({'error': 'No Pub/Sub message received'}), 400

        pubsub_message = envelope.get('message', {})
        if not pubsub_message:
            return jsonify({'error': 'Invalid Pub/Sub message format'}), 400

        # メッセージデータの解析
        data = json.loads(pubsub_message.get('data', '{}'))
        event_type = data.get('type')
        
        logger.info(f"Processing fanout event: {event_type}")

        # イベントタイプに応じた処理
        if event_type == 'post_created':
            return handle_post_created(data)
        elif event_type == 'post_deleted':
            return handle_post_deleted(data)
        else:
            # このサービスでは処理しないイベント
            logger.info(f"Ignoring event type: {event_type}")
            return jsonify({'status': 'ignored', 'event_type': event_type})

    except Exception as e:
        logger.error(f"Error processing fanout event: {e}")
        return jsonify({'error': str(e)}), 500

def handle_post_created(event_data):
    """
    投稿作成時のファンアウト処理
    
    1. 投稿者のフォロワーリストを取得
    2. 各フォロワーのタイムラインに投稿を追加
    3. グローバルタイムラインに追加
    """
    try:
        post_id = event_data.get('postId')
        user_id = event_data.get('userId')
        category = event_data.get('category', 'other')
        timestamp = event_data.get('timestamp')
        
        if not post_id or not user_id:
            raise ValueError("postId and userId are required")

        # タイムスタンプをスコアとして使用
        score = int(datetime.fromisoformat(timestamp.replace('Z', '+00:00')).timestamp() * 1000)
        
        # 1. フォロワーリストを取得
        follower_ids = get_user_followers(user_id)
        logger.info(f"Found {len(follower_ids)} followers for user {user_id}")
        
        # 2. Redis パイプラインで効率的に更新
        pipe = redis_client.pipeline()
        
        # 各フォロワーのタイムラインに追加
        fanout_count = 0
        for follower_id in follower_ids:
            timeline_key = f"timeline:{follower_id}"
            pipe.zadd(timeline_key, {post_id: score})
            
            # タイムラインサイズ制限（最新1000件のみ保持）
            pipe.zremrangebyrank(timeline_key, 0, -1001)
            pipe.expire(timeline_key, 86400 * 7)  # 7日間のTTL
            
            fanout_count += 1
        
        # 作成者自身のタイムラインにも追加
        user_timeline_key = f"timeline:{user_id}"
        pipe.zadd(user_timeline_key, {post_id: score})
        pipe.zremrangebyrank(user_timeline_key, 0, -1001)
        pipe.expire(user_timeline_key, 86400 * 7)
        
        # グローバルタイムラインに追加
        pipe.zadd("global_timeline", {post_id: score})
        pipe.zremrangebyrank("global_timeline", 0, -5001)  # 最新5000件
        
        # カテゴリ別タイムラインに追加
        category_timeline_key = f"global_timeline:{category}"
        pipe.zadd(category_timeline_key, {post_id: score})
        pipe.zremrangebyrank(category_timeline_key, 0, -1001)
        pipe.expire(category_timeline_key, 86400 * 30)  # 30日間のTTL
        
        # 一括実行
        pipe.execute()
        
        logger.info(f"✅ Fanout completed: {fanout_count} timelines updated for post {post_id}")
        
        return jsonify({
            'status': 'success',
            'post_id': post_id,
            'fanout_count': fanout_count,
            'processing_time': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"❌ Error in fanout processing: {e}")
        return jsonify({'error': str(e)}), 500

def handle_post_deleted(event_data):
    """
    投稿削除時の処理
    全てのタイムラインから投稿を削除
    """
    try:
        post_id = event_data.get('postId')
        user_id = event_data.get('userId')
        
        if not post_id:
            raise ValueError("postId is required")

        # フォロワーリストを取得
        follower_ids = get_user_followers(user_id)
        
        # Redis パイプラインで一括削除
        pipe = redis_client.pipeline()
        
        # 各フォロワーのタイムラインから削除
        removal_count = 0
        for follower_id in follower_ids:
            timeline_key = f"timeline:{follower_id}"
            pipe.zrem(timeline_key, post_id)
            removal_count += 1
        
        # 作成者のタイムラインからも削除
        pipe.zrem(f"timeline:{user_id}", post_id)
        
        # グローバルタイムラインから削除
        pipe.zrem("global_timeline", post_id)
        
        # 全カテゴリタイムラインから削除（効率は悪いが確実）
        categories = ['entertainment', 'sports', 'technology', 'education', 'other']
        for category in categories:
            pipe.zrem(f"global_timeline:{category}", post_id)
        
        pipe.execute()
        
        logger.info(f"✅ Post removal completed: {removal_count} timelines updated for post {post_id}")
        
        return jsonify({
            'status': 'success',
            'post_id': post_id,
            'removal_count': removal_count
        })
        
    except Exception as e:
        logger.error(f"❌ Error in post removal: {e}")
        return jsonify({'error': str(e)}), 500

def get_user_followers(user_id):
    """
    ユーザーのフォロワーIDリストを取得
    Redis → Firestore フォールバック
    """
    try:
        # まずRedisから高速取得を試行
        followers_key = f"user_followers:{user_id}"
        follower_ids = redis_client.smembers(followers_key)
        
        if follower_ids:
            logger.info(f"Retrieved {len(follower_ids)} followers from Redis cache")
            return list(follower_ids)
        
        # Redis に データがない場合はFirestoreから取得
        logger.info(f"Cache miss, fetching followers from Firestore for user {user_id}")
        
        follows_ref = firestore_client.collection('follows')
        query = follows_ref.where('followingId', '==', user_id)
        docs = query.stream()
        
        follower_ids = []
        for doc in docs:
            follower_id = doc.to_dict().get('followerId')
            if follower_id:
                follower_ids.append(follower_id)
        
        # Redisにキャッシュ（1時間TTL）
        if follower_ids:
            redis_client.sadd(followers_key, *follower_ids)
            redis_client.expire(followers_key, 3600)
        
        logger.info(f"Retrieved {len(follower_ids)} followers from Firestore")
        return follower_ids
        
    except Exception as e:
        logger.error(f"Error getting followers for user {user_id}: {e}")
        return []

@app.route('/manual-fanout', methods=['POST'])
def manual_fanout():
    """
    手動ファンアウト実行（デバッグ・リカバリ用）
    """
    try:
        data = request.get_json()
        post_id = data.get('post_id')
        user_id = data.get('user_id')
        
        if not post_id or not user_id:
            return jsonify({'error': 'post_id and user_id are required'}), 400
        
        # 投稿データをFirestoreから取得
        post_doc = firestore_client.collection('counts').document(post_id).get()
        if not post_doc.exists:
            return jsonify({'error': 'Post not found'}), 404
        
        post_data = post_doc.to_dict()
        
        # ファンアウトイベントを作成
        event_data = {
            'type': 'post_created',
            'postId': post_id,
            'userId': user_id,
            'category': post_data.get('category', 'other'),
            'timestamp': post_data.get('createdAt', datetime.now()).isoformat()
        }
        
        return handle_post_created(event_data)
        
    except Exception as e:
        logger.error(f"Error in manual fanout: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)