# 🛠️ MVP分析基盤 手動設定手順書

## 前提条件確認

### ✅ 必要なもの
- Google Cloud プロジェクト（Firebase プロジェクトと連携済み）
- `gcloud` CLI インストール済み
- Docker Desktop インストール済み
- 管理者権限でのアクセス

### 📋 プロジェクト情報確認
```bash
# 現在のプロジェクト確認
gcloud config get-value project

# プロジェクト番号確認（後で使用）
gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"
```

**📝 メモ欄**
- プロジェクトID: `_________________`
- プロジェクト番号: `_903887414245____`

---

## 🔥 緊急作業（今すぐ実行）

### ⚠️ 1. 危険なバッチ処理を停止

```bash
# Cloud Scheduler で設定されている場合、以下で確認
gcloud scheduler jobs list

# もし dailyTrendScoreDecay が設定されている場合は削除
gcloud scheduler jobs delete JOB_NAME --location=LOCATION
```

**✅ 確認**: エラーになれば問題なし（元々設定されていない）

---

## 📦 Phase 1: 基盤インフラ構築

### 🚀 1. 必要なAPIを有効化（所要時間: 3分）

```bash
# 必要なAPI一括有効化
gcloud services enable \
  pubsub.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  containerregistry.googleapis.com \
  vpcaccess.googleapis.com \
  cloudfunctions.googleapis.com \
  logging.googleapis.com
```

**✅ 実行結果**: すべて `ENABLED` と表示されればOK

### 📨 2. Pub/Sub トピック作成（所要時間: 1分）

```bash
# analytics-events トピック作成
gcloud pubsub topics create analytics-events

# 作成確認
gcloud pubsub topics list
```

**✅ 確認**: `analytics-events` が表示されればOK

### 🔴 3. Redis インスタンス作成（所要時間: 5-10分）

```bash
# Memorystore Redis 作成（最小構成）
gcloud redis instances create taikichu-analytics-redis \
  --size=1 \
  --region=asia-northeast1 \
  --redis-version=redis_7_0 \
  --tier=basic \
  --network=default
```

**⏳ 待機**: `Creating...` が表示されます。完了まで5-10分かかります。

```bash
# 完了確認（STATE が READY になるまで待機）
gcloud redis instances list
```

**📝 メモ欄**
- Redis ホスト: `_________________`

```bash
# Redis ホスト取得
export REDIS_HOST=$(gcloud redis instances describe taikichu-analytics-redis \
  --region=asia-northeast1 \
  --format="value(host)")

echo "Redis Host: $REDIS_HOST"
```

### 🌐 4. VPC コネクタ作成（所要時間: 3-5分）

```bash
# VPC コネクタ作成
gcloud compute networks vpc-access connectors create redis-connector \
  --region=asia-northeast1 \
  --subnet=default \
  --subnet-project=$(gcloud config get-value project) \
  --min-instances=2 \
  --max-instances=3 \
  --machine-type=e2-micro
```

**⏳ 待機**: 3-5分かかります。

```bash
# 完了確認
gcloud compute networks vpc-access connectors list --region=asia-northeast1
```

---

## 🐳 Phase 2: Cloud Run サービス構築

### 📂 1. analytics-service ディレクトリ作成

```bash
# プロジェクトルートで実行
mkdir -p analytics-service
cd analytics-service

# 必要ファイルをコピー（先ほど作成したファイル）
# main.py, requirements.txt, Dockerfile をこのディレクトリに配置
```

**📋 必要ファイル確認**
- [ ] `main.py`
- [ ] `requirements.txt` 
- [ ] `Dockerfile`

### 🏗️ 2. Docker イメージビルド（所要時間: 5-10分）

```bash
# プロジェクトID設定
export PROJECT_ID=$(gcloud config get-value project)

# Docker イメージビルド
docker build -t gcr.io/$PROJECT_ID/analytics-service:v1 .

# Container Registry にプッシュ
docker push gcr.io/$PROJECT_ID/analytics-service:v1
```

**⏳ 待機**: 初回ビルドは時間がかかります。

### 🚀 3. Cloud Run デプロイ（所要時間: 3分）

```bash
# Redis ホスト設定確認
echo "REDIS_HOST: $REDIS_HOST"

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
```

**📝 メモ欄**
- Cloud Run URL: `_________________`

```bash
# サービスURL取得
export SERVICE_URL=$(gcloud run services describe analytics-service \
  --region=asia-northeast1 \
  --format="value(status.url)")

echo "Service URL: $SERVICE_URL"
```

---

## 🔗 Phase 3: Pub/Sub 接続設定

### 📮 1. サブスクリプション作成

```bash
# Pub/Sub サブスクリプション作成
gcloud pubsub subscriptions create analytics-events-subscription \
  --topic=analytics-events \
  --push-endpoint=$SERVICE_URL/analytics-webhook \
  --ack-deadline=60 \
  --message-retention-duration=7d
```

### 🔐 2. IAM 権限設定

```bash
# プロジェクト番号取得
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Pub/Sub から Cloud Run 呼び出し権限
gcloud run services add-iam-policy-binding analytics-service \
  --region=asia-northeast1 \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

---

## ✅ Phase 4: 動作テスト

### 🏥 1. ヘルスチェック

```bash
# Cloud Run サービス確認
curl -X GET "$SERVICE_URL/health"
```

**✅ 期待される結果**:
```json
{"status": "healthy", "redis": "connected", ...}
```

### 📨 2. テストイベント送信

```bash
# テストメッセージ送信
gcloud pubsub topics publish analytics-events \
  --message='{
    "type": "like_added",
    "countdownId": "test123",
    "userId": "user456",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'
```

### 🔍 3. Redis データ確認

```bash
# Redis CLI インストール（初回のみ）
sudo apt-get update && sudo apt-get install redis-tools

# Redis 接続テスト
redis-cli -h $REDIS_HOST ping

# テストデータ確認
redis-cli -h $REDIS_HOST << EOF
GET trend_score:test123
GET counter:likes:test123
ZRANGE ranking:global 0 -1 WITHSCORES
EOF
```

**✅ 期待される結果**:
```
PONG
"3"
"1"
1) "test123"
2) "3"
```

### 📊 4. API エンドポイント確認

```bash
# ランキングAPI テスト
curl -X GET "$SERVICE_URL/ranking?limit=5"

# トレンドスコアAPI テスト
curl -X GET "$SERVICE_URL/trend-score/test123"
```

---

## 🔧 Phase 5: Cloud Functions 更新

### 📁 1. functions ディレクトリ準備

```bash
# プロジェクトルートに戻る
cd ..

# functions ディレクトリ作成
mkdir -p functions
cd functions

# package.json 作成
cat > package.json << 'EOF'
{
  "name": "taikichu-functions",
  "version": "1.0.0",
  "description": "MVP Analytics Functions",
  "main": "index.js",
  "dependencies": {
    "firebase-admin": "^11.5.0",
    "firebase-functions": "^4.5.0",
    "@google-cloud/pubsub": "^3.7.0"
  },
  "engines": {
    "node": "18"
  }
}
EOF

# 依存関係インストール
npm install
```

### 📝 2. Cloud Functions コード配置

```bash
# mvp_analytics_functions.js を index.js にコピー
cp ../functions/mvp_analytics_functions.js index.js
```

### 🚀 3. Firebase Functions デプロイ

```bash
# Firebase CLI でログイン（まだの場合）
firebase login

# プロジェクト設定
firebase use $PROJECT_ID

# Functions デプロイ
firebase deploy --only functions:onLikeCreate,functions:onLikeDelete,functions:onParticipationCreate,functions:onParticipationDelete,functions:onCommentCreate,functions:publishViewEvent
```

---

## 📱 Phase 6: Flutter アプリ統合

### 🔧 1. 設定ファイル更新

`lib/services/mvp_analytics_client.dart` の `_baseUrl` を実際のURLに更新:

```dart
// 実際のCloud Run URLに置き換え
static const String _baseUrl = 'YOUR_ACTUAL_SERVICE_URL';
```

### 📦 2. 依存関係追加

`pubspec.yaml` に追加:
```yaml
dependencies:
  http: ^1.1.0
  cloud_functions: ^4.5.1
```

```bash
flutter pub get
```

---

## 🎯 Phase 7: 最終確認とメトリクス設定

### 📊 1. 監視ダッシュボード確認

Google Cloud Console で以下を確認:
- Cloud Run メトリクス
- Redis メトリクス
- Pub/Sub メトリクス
- Cloud Functions ログ

### ⚠️ 2. アラート設定

```bash
# Redis メモリ使用率アラート（80%）
gcloud alpha monitoring policies create --policy-from-file=- << 'EOF'
{
  "displayName": "Redis Memory Usage",
  "conditions": [
    {
      "displayName": "Redis memory usage > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"redis_instance\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
```

---

## 💰 コスト監視設定

### 📈 1. 予算アラート設定

Google Cloud Console → Billing → Budgets で以下設定:
- 月額予算: $100
- アラート: 50%, 90%, 100%
- 通知先: あなたのメールアドレス

---

## 🚨 トラブルシューティング

### ❌ よくあるエラーと対処法

#### Redis 接続エラー
```bash
# VPC コネクタ確認
gcloud compute networks vpc-access connectors describe redis-connector --region=asia-northeast1
```

#### Cloud Run デプロイエラー
```bash
# ログ確認
gcloud logs read "resource.type=cloud_run_revision" --limit=20
```

#### Pub/Sub 接続エラー
```bash
# サブスクリプション確認
gcloud pubsub subscriptions describe analytics-events-subscription
```

---

## ✅ 完了チェックリスト

- [ ] Pub/Sub トピック作成完了
- [ ] Redis インスタンス作成完了
- [ ] VPC コネクタ作成完了
- [ ] Cloud Run サービスデプロイ完了
- [ ] Pub/Sub サブスクリプション設定完了
- [ ] テストイベント送信成功
- [ ] Redis データ確認成功
- [ ] API エンドポイント動作確認
- [ ] Cloud Functions デプロイ完了
- [ ] Flutter アプリ統合完了
- [ ] 監視・アラート設定完了

---

## 📞 サポート情報

### 🆘 問題が発生した場合

1. **エラーログ確認**:
   ```bash
   gcloud logs read "severity>=ERROR" --limit=10
   ```

2. **リソース状態確認**:
   ```bash
   gcloud redis instances list
   gcloud run services list
   gcloud pubsub topics list
   ```

3. **コスト確認**:
   Google Cloud Console → Billing → Reports

### 📝 完了報告

すべて完了したら以下情報をメモ:
- Redis Host: `_______________`
- Cloud Run URL: `_______________`
- 総設定時間: `_______________`
- 発生した問題: `_______________`

**🎉 お疲れさまでした！MVP分析基盤の構築が完了しました！**