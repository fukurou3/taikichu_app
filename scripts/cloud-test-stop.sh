#!/bin/bash
# ===============================================
# 🛑 Taikichu App - Cloud Test Environment STOP
# ===============================================

# --- 設定項目 ---
GCP_PROJECT_ID="taikichu-app-c8dcd"
GCP_REGION="asia-northeast1"
REDIS_INSTANCE_NAME="taikichu-redis-test"
CLOUD_RUN_SERVICE_NAME="analytics-service"

# --- 色定義 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}警告：このスクリプトはクラウド上のリソースを完全に削除し、課金を停止します。${NC}"
read -p "クラウドテスト環境を破棄しますか？ この操作は元に戻せません。 (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "操作はキャンセルされました。"
  exit 0
fi

echo ""
echo "--- ステップ1/2: Cloud Runサービスのトラフィックを停止中... ---"
gcloud run services update "$CLOUD_RUN_SERVICE_NAME" \
    --no-traffic \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --quiet

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Cloud Runサービスのトラフィックを停止しました。${NC}"
else
    echo -e "${YELLOW}⚠️  Cloud Runサービスの停止に失敗しました（次のステップに進みます）。${NC}"
fi

echo ""
echo "--- ステップ2/2: Redisインスタンスを削除中 (コスト停止の最重要項目)... ---"
gcloud redis instances delete "$REDIS_INSTANCE_NAME" \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --quiet

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Redisインスタンスの削除に失敗しました。手動でコンソールから削除してください。${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Redisインスタンスを削除しました。${NC}"


echo ""
echo -e "${GREEN}🎉 クラウドテスト環境のクリーンアップが完了しました。不要な課金は停止されています。${NC}"