#!/bin/bash
# Cloud Run用マイクロサービス一括ビルド・デプロイスクリプト
# セキュリティ・パフォーマンス最適化版

set -euo pipefail

# 設定
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
REGISTRY="gcr.io"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# サービス定義（最適化設定付き）
declare -A SERVICES=(
    ["fanout-service"]="cpu=1000m memory=512Mi min=0 max=100"
    ["like-service"]="cpu=2000m memory=1Gi min=1 max=200"
    ["analytics-service"]="cpu=1000m memory=1Gi min=0 max=50"
)

# 前提条件チェック
check_prerequisites() {
    log "前提条件チェック中..."
    
    # gcloud認証チェック
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "gcloud認証が必要です: gcloud auth login"
    fi
    
    # プロジェクト設定チェック
    if [[ "$(gcloud config get-value project)" != "$PROJECT_ID" ]]; then
        log "プロジェクトを設定中: $PROJECT_ID"
        gcloud config set project "$PROJECT_ID"
    fi
    
    # Docker認証
    gcloud auth configure-docker --quiet
    
    # Cloud Run API有効化チェック
    if ! gcloud services list --enabled --filter="name:run.googleapis.com" --format="value(name)" | grep -q run.googleapis.com; then
        log "Cloud Run API を有効化中..."
        gcloud services enable run.googleapis.com
    fi
    
    log "✅ 前提条件チェック完了"
}

# マルチアーキテクチャビルド（ARM64対応）
build_image() {
    local service_name=$1
    local service_dir=$2
    local image_tag="${REGISTRY}/${PROJECT_ID}/${service_name}:latest"
    
    log "🐳 ビルド開始: $service_name"
    
    cd "$service_dir"
    
    # セキュリティスキャン用のラベル追加
    docker build \
        --platform linux/amd64 \
        --label "maintainer=taikichu-team" \
        --label "version=$(date +%Y%m%d-%H%M%S)" \
        --label "service=$service_name" \
        --no-cache \
        -t "$image_tag" .
    
    log "✅ ビルド完了: $service_name"
    
    # イメージプッシュ
    log "📤 プッシュ中: $image_tag"
    docker push "$image_tag"
    
    log "✅ プッシュ完了: $service_name"
    
    cd - > /dev/null
}

# Cloud Runデプロイ（最適化設定付き）
deploy_service() {
    local service_name=$1
    local service_config=$2
    local image_tag="${REGISTRY}/${PROJECT_ID}/${service_name}:latest"
    
    # 設定パース
    local cpu=$(echo "$service_config" | grep -o 'cpu=[^ ]*' | cut -d'=' -f2)
    local memory=$(echo "$service_config" | grep -o 'memory=[^ ]*' | cut -d'=' -f2)
    local min_scale=$(echo "$service_config" | grep -o 'min=[^ ]*' | cut -d'=' -f2)
    local max_scale=$(echo "$service_config" | grep -o 'max=[^ ]*' | cut -d'=' -f2)
    
    log "🚀 デプロイ開始: $service_name"
    
    # サービス作成・更新
    gcloud run deploy "$service_name" \
        --image="$image_tag" \
        --platform=managed \
        --region="$REGION" \
        --allow-unauthenticated \
        --service-account="${service_name}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="REDIS_HOST=10.0.0.3,REDIS_PORT=6379,PROJECT_ID=$PROJECT_ID" \
        --cpu="$cpu" \
        --memory="$memory" \
        --min-instances="$min_scale" \
        --max-instances="$max_scale" \
        --concurrency=80 \
        --timeout=300 \
        --execution-environment=gen2 \
        --cpu-throttling=false \
        --port=8080 \
        --quiet
    
    log "✅ デプロイ完了: $service_name"
    
    # URL取得
    local service_url=$(gcloud run services describe "$service_name" \
        --region="$REGION" \
        --format="value(status.url)")
    
    log "🌐 サービスURL: $service_url"
}

# IAMサービスアカウント作成
create_service_accounts() {
    log "🔐 サービスアカウント設定中..."
    
    for service_name in "${!SERVICES[@]}"; do
        local sa_email="${service_name}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        # サービスアカウント存在チェック
        if ! gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
            log "サービスアカウント作成: $sa_email"
            gcloud iam service-accounts create "$service_name" \
                --display-name="$service_name Service Account" \
                --description="Dedicated service account for $service_name microservice"
        fi
        
        # 必要な権限付与
        local roles=(
            "roles/cloudsql.client"
            "roles/redis.editor"
            "roles/pubsub.subscriber"
            "roles/pubsub.publisher"
            "roles/datastore.user"
            "roles/logging.logWriter"
            "roles/monitoring.metricWriter"
        )
        
        for role in "${roles[@]}"; do
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa_email" \
                --role="$role" \
                --quiet > /dev/null
        done
    done
    
    log "✅ サービスアカウント設定完了"
}

# ヘルスチェック
health_check() {
    log "🏥 ヘルスチェック実行中..."
    
    for service_name in "${!SERVICES[@]}"; do
        local service_url=$(gcloud run services describe "$service_name" \
            --region="$REGION" \
            --format="value(status.url)" 2>/dev/null || echo "")
        
        if [[ -n "$service_url" ]]; then
            log "チェック中: $service_name"
            if curl -f -s "$service_url/health" > /dev/null; then
                log "✅ $service_name: 正常"
            else
                warn "⚠️ $service_name: 応答なし"
            fi
        else
            warn "⚠️ $service_name: サービスURL取得失敗"
        fi
    done
}

# クリーンアップ
cleanup() {
    log "🧹 クリーンアップ中..."
    
    # 古いイメージを削除（最新5個を保持）
    for service_name in "${!SERVICES[@]}"; do
        local images=$(gcloud container images list-tags "${REGISTRY}/${PROJECT_ID}/${service_name}" \
            --limit=999 --sort-by=~TIMESTAMP --format="value(digest)" | tail -n +6)
        
        if [[ -n "$images" ]]; then
            log "古いイメージ削除: $service_name"
            echo "$images" | while read digest; do
                gcloud container images delete "${REGISTRY}/${PROJECT_ID}/${service_name}@${digest}" --quiet &
            done
            wait
        fi
    done
    
    # ローカルDockerイメージクリーンアップ
    docker image prune -f > /dev/null
    
    log "✅ クリーンアップ完了"
}

# メイン実行
main() {
    log "🚀 Cloud Run マイクロサービス デプロイ開始"
    
    check_prerequisites
    create_service_accounts
    
    # 各サービスのビルド・デプロイ
    for service_name in "${!SERVICES[@]}"; do
        local service_config="${SERVICES[$service_name]}"
        
        if [[ -d "$service_name" ]]; then
            build_image "$service_name" "$service_name"
            deploy_service "$service_name" "$service_config"
        else
            warn "サービスディレクトリが見つかりません: $service_name"
        fi
    done
    
    # 最終チェック
    sleep 10  # サービス起動待ち
    health_check
    cleanup
    
    log "🎉 全サービスデプロイ完了"
    
    # サマリー表示
    log "📊 デプロイサマリー:"
    for service_name in "${!SERVICES[@]}"; do
        local service_url=$(gcloud run services describe "$service_name" \
            --region="$REGION" \
            --format="value(status.url)" 2>/dev/null || echo "N/A")
        echo "  - $service_name: $service_url"
    done
}

# スクリプト引数処理
case "${1:-all}" in
    "all")
        main
        ;;
    "build")
        check_prerequisites
        for service_name in "${!SERVICES[@]}"; do
            [[ -d "$service_name" ]] && build_image "$service_name" "$service_name"
        done
        ;;
    "deploy")
        check_prerequisites
        for service_name in "${!SERVICES[@]}"; do
            deploy_service "$service_name" "${SERVICES[$service_name]}"
        done
        ;;
    "health")
        health_check
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        echo "使用方法: $0 [all|build|deploy|health|cleanup]"
        exit 1
        ;;
esac