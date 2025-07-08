#!/bin/bash
# ===============================================
# 🚀 Taikichu App - Cloud Test Environment START
# ===============================================

# --- 設定項目 ---
# プロジェクトIDやリージョンを君の環境に合わせて設定する
GCP_PROJECT_ID="taikichu-app-c8dcd"
GCP_REGION="asia-northeast1"
REDIS_INSTANCE_NAME="taikichu-redis-test" # テスト用とわかるように-testをつける
CLOUD_RUN_SERVICE_NAME="analytics-service"

# --- 色定義 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}警告：このスクリプトはGoogle Cloud Platform上に課金対象のリソースを作成します。${NC}"
read -p "クラウドテスト環境の構築を開始しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "操作はキャンセルされました。"
  exit 0
fi

echo ""
echo "--- ステップ1/2: Redisインスタンスを作成中... (数分かかります) ---"
gcloud redis instances create "$REDIS_INSTANCE_NAME" \
    --size=1 \
    --region="$GCP_REGION" \
    --redis-version=redis_6_x \
    --project="$GCP_PROJECT_ID"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Redisインスタンスの作成に失敗しました。${NC}"
    exit 1
fi
REDIS_IP=$(gcloud redis instances describe "$REDIS_INSTANCE_NAME" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" --format="value(host)")
echo -e "${GREEN}✅ Redisインスタンスが作成されました。IP: $REDIS_IP${NC}"

echo ""
echo "--- ステップ2/2: Cloud Runサービスをデプロイ中... ---"
gcloud run deploy "$CLOUD_RUN_SERVICE_NAME" \
    --source="./analytics-service" \
    --platform=managed \
    --region="$GCP_REGION" \
    --allow-unauthenticated \
    --set-env-vars="REDIS_HOST=$REDIS_IP,REDIS_PORT=6379,ENVIRONMENT=production" \
    --project="$GCP_PROJECT_ID"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Cloud Runサービスのデプロイに失敗しました。${NC}"
    exit 1
fi

SERVICE_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE_NAME" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" --format="value(status.url)")
echo -e "${GREEN}✅ Cloud Runサービスがデプロイされました。URL: $SERVICE_URL${NC}"

echo ""
echo -e "${GREEN}🎉 クラウドテスト環境の準備が完了しました。${NC}"
echo -e "${YELLOW}テストが終了したら、必ず 'cloud-test-stop.sh' を実行してリソースを削除してください。${NC}"