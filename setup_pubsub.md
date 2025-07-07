# Pub/Sub トピック作成手順

## 前提条件
- Google Cloud プロジェクトが作成済み
- Firebase プロジェクトと連携済み
- `gcloud` CLI がインストール済み

## 1. 認証とプロジェクト設定

```bash
# Google Cloud にログイン
gcloud auth login

# プロジェクト設定（YOUR_PROJECT_IDを実際のプロジェクトIDに置き換え）
gcloud config set project YOUR_PROJECT_ID

# 現在のプロジェクト確認
gcloud config get-value project
```

## 2. 必要なAPIの有効化

```bash
# Pub/Sub API を有効化
gcloud services enable pubsub.googleapis.com

# Cloud Run API を有効化（後のステップで使用）
gcloud services enable run.googleapis.com

# Redis API を有効化（後のステップで使用）
gcloud services enable redis.googleapis.com
```

## 3. Pub/Sub トピックの作成

```bash
# analytics-events トピックを作成
gcloud pubsub topics create analytics-events

# 作成確認
gcloud pubsub topics list
```

## 4. Pub/Sub サブスクリプションの作成

```bash
# Cloud Run用のプッシュサブスクリプション作成
# ENDPOINT_URLは後でCloud RunのURLに置き換えます
gcloud pubsub subscriptions create analytics-events-subscription \
    --topic=analytics-events \
    --push-endpoint=https://ENDPOINT_URL/analytics-webhook \
    --ack-deadline=60

# サブスクリプション確認
gcloud pubsub subscriptions list
```

## 5. IAM権限設定

```bash
# Cloud Functions に Pub/Sub Publisher 権限を付与
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:YOUR_PROJECT_ID@appspot.gserviceaccount.com" \
    --role="roles/pubsub.publisher"

# Cloud Run に Pub/Sub Subscriber 権限を付与
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:YOUR_PROJECT_ID@appspot.gserviceaccount.com" \
    --role="roles/pubsub.subscriber"
```

## 6. テストメッセージの送信

```bash
# テストメッセージを送信
gcloud pubsub topics publish analytics-events \
    --message='{"event": "test", "countdownId": "test123", "timestamp": "2024-01-01T00:00:00Z"}'

# メッセージ受信確認（開発中のみ）
gcloud pubsub subscriptions pull analytics-events-subscription \
    --auto-ack \
    --limit=1
```

## 7. 料金確認

```bash
# Pub/Sub の使用量確認
gcloud logging read "resource.type=pubsub_topic" \
    --limit=10 \
    --format="table(timestamp, resource.labels.topic_id, jsonPayload.message)"
```

## 無料枠の詳細

- **Pub/Sub**: 月間10GBまで無料
- **メッセージ数**: 月間1000万メッセージまで無料
- **ストレージ**: 30日分まで無料

## 次のステップ

1. Cloud Functions の修正（イベント発行専用化）
2. Cloud Run サービスの構築
3. Memorystore for Redis の設定

## トラブルシューティング

### エラー: Permission denied
```bash
# サービスアカウントキーを作成
gcloud iam service-accounts keys create key.json \
    --iam-account=YOUR_PROJECT_ID@appspot.gserviceaccount.com

# 環境変数設定
export GOOGLE_APPLICATION_CREDENTIALS="key.json"
```

### エラー: Topic already exists
```bash
# 既存トピック削除（必要な場合のみ）
gcloud pubsub topics delete analytics-events

# 再作成
gcloud pubsub topics create analytics-events
```