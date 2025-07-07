# Memorystore for Redis セットアップ手順

## 1. Redis インスタンス作成

```bash
# プロジェクト設定確認
gcloud config get-value project

# 最小構成のRedisインスタンス作成
gcloud redis instances create taikichu-analytics-redis \
    --size=1 \
    --region=asia-northeast1 \
    --redis-version=redis_7_0 \
    --tier=basic \
    --network=default

# 作成確認
gcloud redis instances list
```

## 2. 接続情報取得

```bash
# Redis インスタンス詳細取得
gcloud redis instances describe taikichu-analytics-redis \
    --region=asia-northeast1

# IPアドレス取得
export REDIS_HOST=$(gcloud redis instances describe taikichu-analytics-redis \
    --region=asia-northeast1 \
    --format="value(host)")

echo "Redis Host: $REDIS_HOST"
```

## 3. ネットワーク設定

```bash
# VPC ファイアウォール設定（必要に応じて）
gcloud compute firewall-rules create allow-redis \
    --allow tcp:6379 \
    --source-ranges=10.0.0.0/8 \
    --description="Allow Redis access from internal network"
```

## 4. 接続テスト

```bash
# Cloud Shell から接続テスト
sudo apt-get update
sudo apt-get install redis-tools

# 接続確認
redis-cli -h $REDIS_HOST ping
```

## 5. 初期データ設定（開発用）

```bash
# テストデータ投入
redis-cli -h $REDIS_HOST << EOF
SET trend_score:test123 100.5
SET counter:likes:test123 50
SET counter:participants:test123 25
ZADD ranking:global 100.5 test123
EOF

# データ確認
redis-cli -h $REDIS_HOST << EOF
GET trend_score:test123
GET counter:likes:test123
ZRANGE ranking:global 0 -1 WITHSCORES
EOF
```

## 6. 監視設定

```bash
# Redis メトリクス有効化
gcloud services enable monitoring.googleapis.com

# アラートポリシー作成（メモリ使用率80%）
gcloud alpha monitoring policies create \
    --policy-from-file=redis-monitoring-policy.json
```

## 料金情報

### Basic ティア（1GB）
- **月額**: 約 $50-60
- **メモリ**: 1GB
- **接続数**: 最大1000
- **可用性**: 99.9%

### Standard ティア（推奨・本番用）
- **月額**: 約 $100-120
- **メモリ**: 1GB（レプリケーション込み）
- **接続数**: 最大1000
- **可用性**: 99.95%
- **自動フェイルオーバー**: あり

## 7. Cloud Run との接続設定

```bash
# Cloud Run サービスから Redis に接続するための環境変数
export REDIS_HOST=$REDIS_HOST
export REDIS_PORT=6379
```

## 8. セキュリティ設定

```bash
# AUTH 文字列設定（オプション）
gcloud redis instances update taikichu-analytics-redis \
    --region=asia-northeast1 \
    --auth-enabled

# AUTH 文字列取得
gcloud redis instances get-auth-string taikichu-analytics-redis \
    --region=asia-northeast1
```

## 9. バックアップ設定

```bash
# 手動スナップショット作成
gcloud redis instances export taikichu-analytics-redis \
    --region=asia-northeast1 \
    --destination=gs://YOUR_BUCKET/redis-backup-$(date +%Y%m%d).rdb
```

## 10. 監視ダッシュボード

### Cloud Console での確認項目
- メモリ使用率
- 秒間接続数
- 秒間コマンド数
- キー数
- レイテンシー

### アラート設定推奨値
- メモリ使用率 > 80%
- 接続数 > 800
- エラー率 > 1%

## トラブルシューティング

### 接続エラー
```bash
# ネットワーク確認
gcloud compute networks list
gcloud compute firewall-rules list --filter="name:redis"

# Redis ステータス確認
gcloud redis instances describe taikichu-analytics-redis \
    --region=asia-northeast1 \
    --format="value(state)"
```

### パフォーマンス問題
```bash
# メモリ使用量確認
redis-cli -h $REDIS_HOST info memory

# キー分布確認
redis-cli -h $REDIS_HOST --scan --pattern "*" | head -20
```

## 次のステップ

1. Cloud Run サービスのデプロイ
2. Pub/Sub サブスクリプション設定の更新
3. クライアントアプリからのRedis読み取り実装