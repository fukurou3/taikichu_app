"""
いいね処理専用マイクロサービス
責任: いいね/アンいいね処理とカウンター更新のみ

完全に独立したサービス - 他の機能の障害に影響されない
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
        redis_client.ping()
        return jsonify({
            'status': 'healthy',
            'service': 'like-service',
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e)
        }), 500

@app.route('/process-event', methods=['POST'])
def process_like_event():
    """
    Pub/Subからのいいねイベント処理
    """
    try:
        envelope = request.get_json()
        if not envelope:
            return jsonify({'error': 'No Pub/Sub message received'}), 400

        pubsub_message = envelope.get('message', {})
        data = json.loads(pubsub_message.get('data', '{}'))
        event_type = data.get('type')
        
        logger.info(f"Processing like event: {event_type}")

        if event_type == 'like_added':
            return handle_like_added(data)
        elif event_type == 'like_removed':
            return handle_like_removed(data)
        else:
            logger.info(f"Ignoring event type: {event_type}")
            return jsonify({'status': 'ignored', 'event_type': event_type})

    except Exception as e:
        logger.error(f"Error processing like event: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/like', methods=['POST'])
def add_like():
    """
    いいね追加API（直接呼び出し用）
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        post_id = data.get('post_id')
        
        if not user_id or not post_id:
            return jsonify({'error': 'user_id and post_id are required'}), 400
        
        # 重複チェック
        if is_already_liked(user_id, post_id):
            return jsonify({'error': 'Already liked'}), 409
        
        # 1. Firestoreにいいねレコード作成
        like_id = f"{user_id}_{post_id}"
        like_data = {
            'userId': user_id,
            'countdownId': post_id,
            'createdAt': firestore.SERVER_TIMESTAMP
        }
        
        firestore_client.collection('likes').document(like_id).set(like_data)
        
        # 2. Redis カウンター更新
        update_like_counter(post_id, 1)
        
        # 3. ユーザーのいいね状態更新
        set_user_like_status(user_id, post_id, True)
        
        logger.info(f"✅ Like added: user {user_id} liked post {post_id}")
        
        return jsonify({
            'status': 'success',
            'like_id': like_id,
            'action': 'added'
        })
        
    except Exception as e:
        logger.error(f"❌ Error adding like: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/unlike', methods=['POST'])
def remove_like():
    """
    いいね削除API
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        post_id = data.get('post_id')
        
        if not user_id or not post_id:
            return jsonify({'error': 'user_id and post_id are required'}), 400
        
        # 存在チェック
        if not is_already_liked(user_id, post_id):
            return jsonify({'error': 'Like not found'}), 404
        
        # 1. Firestoreからいいねレコード削除
        like_id = f"{user_id}_{post_id}"
        firestore_client.collection('likes').document(like_id).delete()
        
        # 2. Redis カウンター更新
        update_like_counter(post_id, -1)
        
        # 3. ユーザーのいいね状態更新
        set_user_like_status(user_id, post_id, False)
        
        logger.info(f"✅ Like removed: user {user_id} unliked post {post_id}")
        
        return jsonify({
            'status': 'success',
            'like_id': like_id,
            'action': 'removed'
        })
        
    except Exception as e:
        logger.error(f"❌ Error removing like: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/count/<post_id>', methods=['GET'])
def get_like_count(post_id):
    """
    投稿のいいね数取得
    """
    try:
        count = get_like_count_from_redis(post_id)
        return jsonify({
            'post_id': post_id,
            'count': count,
            'source': 'redis'
        })
    except Exception as e:
        logger.error(f"Error getting like count: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status/<user_id>/<post_id>', methods=['GET'])
def get_like_status(user_id, post_id):
    """
    ユーザーの特定投稿に対するいいね状態取得
    """
    try:
        liked = is_already_liked(user_id, post_id)
        return jsonify({
            'user_id': user_id,
            'post_id': post_id,
            'liked': liked
        })
    except Exception as e:
        logger.error(f"Error getting like status: {e}")
        return jsonify({'error': str(e)}), 500

def handle_like_added(event_data):
    """
    いいね追加イベント処理
    """
    try:
        user_id = event_data.get('userId')
        post_id = event_data.get('countdownId')
        
        if not user_id or not post_id:
            raise ValueError("userId and countdownId are required")
        
        # Redis カウンター更新
        update_like_counter(post_id, 1)
        
        # ユーザーのいいね状態更新
        set_user_like_status(user_id, post_id, True)
        
        logger.info(f"✅ Like event processed: {user_id} liked {post_id}")
        
        return jsonify({
            'status': 'success',
            'event_type': 'like_added',
            'user_id': user_id,
            'post_id': post_id
        })
        
    except Exception as e:
        logger.error(f"❌ Error handling like added event: {e}")
        return jsonify({'error': str(e)}), 500

def handle_like_removed(event_data):
    """
    いいね削除イベント処理
    """
    try:
        user_id = event_data.get('userId')
        post_id = event_data.get('countdownId')
        
        if not user_id or not post_id:
            raise ValueError("userId and countdownId are required")
        
        # Redis カウンター更新
        update_like_counter(post_id, -1)
        
        # ユーザーのいいね状態更新
        set_user_like_status(user_id, post_id, False)
        
        logger.info(f"✅ Unlike event processed: {user_id} unliked {post_id}")
        
        return jsonify({
            'status': 'success',
            'event_type': 'like_removed',
            'user_id': user_id,
            'post_id': post_id
        })
        
    except Exception as e:
        logger.error(f"❌ Error handling like removed event: {e}")
        return jsonify({'error': str(e)}), 500

def update_like_counter(post_id, delta):
    """
    Redis のいいねカウンター更新
    """
    try:
        counter_key = f"counter:{post_id}"
        
        # いいね数を増減
        new_count = redis_client.hincrby(counter_key, "likes", delta)
        
        # カウンターが0未満にならないよう制限
        if new_count < 0:
            redis_client.hset(counter_key, "likes", 0)
            new_count = 0
        
        # TTLを設定（30日）
        redis_client.expire(counter_key, 86400 * 30)
        
        logger.info(f"Like counter updated: post {post_id} = {new_count}")
        return new_count
        
    except Exception as e:
        logger.error(f"Error updating like counter: {e}")
        raise

def get_like_count_from_redis(post_id):
    """
    Redisからいいね数取得
    """
    try:
        counter_key = f"counter:{post_id}"
        count = redis_client.hget(counter_key, "likes")
        return int(count) if count else 0
    except Exception as e:
        logger.error(f"Error getting like count from Redis: {e}")
        return 0

def is_already_liked(user_id, post_id):
    """
    ユーザーが既にいいねしているかチェック
    Redis → Firestore フォールバック
    """
    try:
        # まずRedisから高速チェック
        like_key = f"user_like:{user_id}:{post_id}"
        status = redis_client.get(like_key)
        
        if status is not None:
            return status == 'true'
        
        # Redisにない場合はFirestoreから確認
        like_id = f"{user_id}_{post_id}"
        like_doc = firestore_client.collection('likes').document(like_id).get()
        
        liked = like_doc.exists
        
        # Redisにキャッシュ（1時間TTL）
        redis_client.setex(like_key, 3600, 'true' if liked else 'false')
        
        return liked
        
    except Exception as e:
        logger.error(f"Error checking like status: {e}")
        return False

def set_user_like_status(user_id, post_id, liked):
    """
    ユーザーのいいね状態をRedisに保存
    """
    try:
        like_key = f"user_like:{user_id}:{post_id}"
        redis_client.setex(like_key, 3600, 'true' if liked else 'false')
    except Exception as e:
        logger.error(f"Error setting like status: {e}")

@app.route('/batch-sync', methods=['POST'])
def batch_sync_counters():
    """
    Redisカウンターの一括同期（メンテナンス用）
    """
    try:
        # 全投稿のいいね数をFirestoreから再計算
        posts_ref = firestore_client.collection('counts')
        
        sync_count = 0
        for post_doc in posts_ref.stream():
            post_id = post_doc.id
            
            # Firestoreでいいね数をカウント
            likes_count = firestore_client.collection('likes')\
                .where('countdownId', '==', post_id)\
                .get()\
                .size
            
            # Redisを更新
            counter_key = f"counter:{post_id}"
            redis_client.hset(counter_key, "likes", likes_count)
            redis_client.expire(counter_key, 86400 * 30)
            
            sync_count += 1
            
            if sync_count % 100 == 0:
                logger.info(f"Synced {sync_count} posts...")
        
        logger.info(f"✅ Batch sync completed: {sync_count} posts")
        
        return jsonify({
            'status': 'success',
            'synced_posts': sync_count
        })
        
    except Exception as e:
        logger.error(f"❌ Error in batch sync: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)