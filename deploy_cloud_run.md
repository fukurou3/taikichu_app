# Cloud Run リアルタイム分析サービス デプロイ手順

## 前提条件
- Memorystore for Redis が作成済み
- Pub/Sub トピック `analytics-events` が作成済み

## 1. Docker イメージのビルドと登録

```bash
# プロジェクト設定
export PROJECT_ID=$(gcloud config get-value project)
echo "Project ID: $PROJECT_ID"

# Container Registry 有効化
gcloud services enable containerregistry.googleapis.com

# analytics-service ディレクトリに移動
cd analytics-service

# Docker イメージビルド
docker build -t gcr.io/$PROJECT_ID/analytics-service:v1 .

# イメージをContainer Registryにプッシュ
docker push gcr.io/$PROJECT_ID/analytics-service:v1
```

## 2. Cloud Run サービスのデプロイ

```bash
# Redis ホスト取得
export REDIS_HOST=$(gcloud redis instances describe taikichu-analytics-redis \
    --region=asia-northeast1 \
    --format="value(host)")

echo "Redis Host: $REDIS_HOST"

# Cloud Run サービスデプロイ
gcloud run deploy analytics-service \
    --image=gcr.io/$PROJECT_ID/analytics-service:v1 \
    --platform=managed \
    --region=asia-northeast1 \
    --allow-unauthenticated \
    --memory=512Mi \
    --cpu=1 \
    --concurrency=100 \
    --max-instances=10 \
    --set-env-vars="REDIS_HOST=$REDIS_HOST,REDIS_PORT=6379" \
    --vpc-connector=projects/$PROJECT_ID/locations/asia-northeast1/connectors/redis-connector

# サービスURL取得
export SERVICE_URL=$(gcloud run services describe analytics-service \
    --region=asia-northeast1 \
    --format="value(status.url)")

echo "Service URL: $SERVICE_URL"
```

## 3. VPC コネクタ作成（Redis接続用）

```bash
# Serverless VPC Access API 有効化
gcloud services enable vpcaccess.googleapis.com

# VPC コネクタ作成
gcloud compute networks vpc-access connectors create redis-connector \
    --region=asia-northeast1 \
    --subnet=default \
    --subnet-project=$PROJECT_ID \
    --min-instances=2 \
    --max-instances=3 \
    --machine-type=e2-micro

# コネクタ確認
gcloud compute networks vpc-access connectors list --region=asia-northeast1
```

## 4. Pub/Sub サブスクリプション更新

```bash
# 既存サブスクリプション削除
gcloud pubsub subscriptions delete analytics-events-subscription

# 新しいプッシュサブスクリプション作成
gcloud pubsub subscriptions create analytics-events-subscription \
    --topic=analytics-events \
    --push-endpoint=$SERVICE_URL/analytics-webhook \
    --ack-deadline=60 \
    --message-retention-duration=7d

# サブスクリプション確認
gcloud pubsub subscriptions describe analytics-events-subscription
```

## 5. IAM 権限設定

```bash
# Cloud Run サービスアカウント取得
export SERVICE_ACCOUNT=$(gcloud run services describe analytics-service \
    --region=asia-northeast1 \
    --format="value(spec.template.spec.serviceAccountName)")

# Pub/Sub からCloud Run呼び出し権限
gcloud run services add-iam-policy-binding analytics-service \
    --region=asia-northeast1 \
    --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/run.invoker"

# Redis アクセス権限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/redis.editor"
```

## 6. 動作テスト

```bash
# ヘルスチェック
curl -X GET "$SERVICE_URL/health"

# テストイベント送信
gcloud pubsub topics publish analytics-events \
    --message='{
        "type": "like_added",
        "countdownId": "test123",
        "userId": "user456",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }'

# Redis データ確認
redis-cli -h $REDIS_HOST << EOF
GET trend_score:test123
GET counter:likes:test123
ZRANGE ranking:global 0 -1 WITHSCORES
EOF

# ランキングAPI テスト
curl -X GET "$SERVICE_URL/ranking?limit=10"

# トレンドスコアAPI テスト
curl -X GET "$SERVICE_URL/trend-score/test123"
```

## 7. 監視設定

```bash
# Cloud Run メトリクス確認
gcloud run services describe analytics-service \
    --region=asia-northeast1 \
    --format="value(status.conditions)"

# ログ確認
gcloud logs read "resource.type=cloud_run_revision" \
    --filter="resource.labels.service_name=analytics-service" \
    --limit=20
```

## 8. オートスケーリング設定

```bash
# CPU使用率ベースのスケーリング設定更新
gcloud run services update analytics-service \
    --region=asia-northeast1 \
    --cpu-throttling \
    --concurrency=50 \
    --min-instances=1 \
    --max-instances=20
```

## パフォーマンス設定

### 推奨設定（本番環境）
```bash
gcloud run services update analytics-service \
    --region=asia-northeast1 \
    --memory=1Gi \
    --cpu=1 \
    --concurrency=80 \
    --max-instances=50 \
    --min-instances=2
```

### 開発環境設定
```bash
gcloud run services update analytics-service \
    --region=asia-northeast1 \
    --memory=512Mi \
    --cpu=1 \
    --concurrency=100 \
    --max-instances=5 \
    --min-instances=0
```

## 料金予測

### 無料枠（月間）
- **Cloud Run**: 200万リクエスト, 40万GB-s
- **Container Registry**: 500MB
- **VPC Access**: 設定による

### 有料使用時の概算
- **1万イベント/日**: $10-15/月
- **10万イベント/日**: $50-70/月
- **100万イベント/日**: $200-300/月

## トラブルシューティング

### デプロイエラー
```bash
# ビルドログ確認
gcloud builds list --limit=5

# サービスログ確認
gcloud logs read "resource.type=cloud_run_revision" \
    --filter="resource.labels.service_name=analytics-service AND severity>=ERROR" \
    --limit=10
```

### Redis接続エラー
```bash
# VPCコネクタ確認
gcloud compute networks vpc-access connectors describe redis-connector \
    --region=asia-northeast1

# Redis インスタンス確認
gcloud redis instances describe taikichu-analytics-redis \
    --region=asia-northeast1
```

### Pub/Sub 接続エラー
```bash
# サブスクリプション確認
gcloud pubsub subscriptions describe analytics-events-subscription

# プッシュエンドポイント確認
gcloud pubsub subscriptions describe analytics-events-subscription \
    --format="value(pushConfig.pushEndpoint)"
```

## 次のステップ

1. Flutter アプリからのRedis読み取り実装
2. パフォーマンス監視とチューニング
3. エラーハンドリングの強化