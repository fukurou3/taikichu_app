#!/bin/bash
# ==================================
# 🚨 TAICHU APP - EMERGENCY STOP 🚨
# ==================================

echo "⚠️  これは本番環境を停止させる緊急用スクリプトです。"
read -p "本当に実行しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "操作はキャンセルされました。"
  exit 0
fi

echo "--- ステップ1: Cloud Run サービスのトラフィックを停止中... ---"
gcloud run services update analytics-service --no-traffic --region=asia-northeast1

echo "--- ステップ2: Redisインスタンスを削除中 (コスト停止の最重要項目)... ---"
gcloud redis instances delete taikichu-redis --region=asia-northeast1 --quiet

echo "--- ステップ3: Firebase Functionsを無効化中... ---"
# ここに無効化したい関数をリストアップする
FUNCTIONS_TO_DELETE=(
  "onLikeCreate"
  "onLikeDelete"
  "onParticipationCreate"
  "onParticipationDelete"
  "onCommentCreate"
)

for func in "${FUNCTIONS_TO_DELETE[@]}"; do
  echo "Deleting function: $func"
  gcloud functions delete "$func" --region=us-central1 --quiet
done

echo "✅ 緊急停止プロトコルが完了しました。"