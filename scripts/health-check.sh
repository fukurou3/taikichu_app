#!/bin/bash
# 🩺 Taikichu App - 統合ヘルスチェックスクリプト
# =============================================

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 設定
TIMEOUT=5
VERBOSE=false

# 使用方法表示
show_usage() {
    echo ""
    echo -e "${BLUE}🩺 Taikichu App ヘルスチェック${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  -v, --verbose    詳細情報を表示"
    echo "  -t, --timeout N  タイムアウト時間（秒）"
    echo "  -h, --help       このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0                # 基本ヘルスチェック"
    echo "  $0 -v            # 詳細モード"
    echo "  $0 -t 10         # 10秒タイムアウト"
    echo ""
}

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ 不明なオプション: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# ログ関数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# ヘルスチェック開始
echo ""
log_info "統合ヘルスチェックを開始します..."
echo ""

# 全体の結果を記録
OVERALL_STATUS=0

# 1. Docker環境確認
log_info "🐳 Docker 環境確認中..."
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        log_success "Docker 環境 OK"
        if $VERBOSE; then
            echo "    Docker Version: $(docker --version)"
        fi
    else
        log_error "Docker デーモンが起動していません"
        OVERALL_STATUS=1
    fi
else
    log_error "Docker がインストールされていません"
    OVERALL_STATUS=1
fi

# 2. Docker Compose確認
if command -v docker-compose &> /dev/null; then
    log_success "Docker Compose OK"
    if $VERBOSE; then
        echo "    Docker Compose Version: $(docker-compose --version)"
    fi
else
    log_error "Docker Compose がインストールされていません"
    OVERALL_STATUS=1
fi

echo ""

# 3. サービス稼働状況確認
log_info "📊 サービス稼働状況確認中..."
if docker-compose ps | grep -q "Up"; then
    log_success "Docker Compose サービス稼働中"
    if $VERBOSE; then
        echo ""
        docker-compose ps
        echo ""
    fi
else
    log_warning "Docker Compose サービスが起動していません"
    log_info "サービスを起動するには: docker-compose up -d"
    OVERALL_STATUS=1
fi

echo ""

# 4. 個別サービス確認
log_info "🔍 個別サービス確認中..."

# Redis確認
log_info "Redis 接続確認..."
if docker exec taikichu-redis-local redis-cli ping &> /dev/null; then
    REDIS_RESPONSE=$(docker exec taikichu-redis-local redis-cli ping 2>/dev/null)
    if [ "$REDIS_RESPONSE" = "PONG" ]; then
        log_success "Redis 接続 OK"
        if $VERBOSE; then
            REDIS_INFO=$(docker exec taikichu-redis-local redis-cli INFO stats 2>/dev/null | head -5)
            echo "    Redis Stats:"
            echo "$REDIS_INFO" | sed 's/^/      /'
        fi
    else
        log_error "Redis 応答異常"
        OVERALL_STATUS=1
    fi
else
    log_error "Redis 接続失敗"
    OVERALL_STATUS=1
fi

# Analytics Service確認
log_info "Analytics Service 確認..."
if curl -sf "http://localhost:8080/health" --max-time $TIMEOUT &> /dev/null; then
    log_success "Analytics Service OK"
    if $VERBOSE; then
        ANALYTICS_RESPONSE=$(curl -s "http://localhost:8080/health" 2>/dev/null)
        echo "    Response: $ANALYTICS_RESPONSE"
    fi
else
    log_error "Analytics Service 接続失敗"
    OVERALL_STATUS=1
fi

# Firebase Emulator UI確認
log_info "Firebase Emulator UI 確認..."
if curl -sf "http://localhost:4000" --max-time $TIMEOUT &> /dev/null; then
    log_success "Firebase Emulator UI OK"
else
    log_error "Firebase Emulator UI 接続失敗"
    OVERALL_STATUS=1
fi

# Firestore Emulator確認
log_info "Firestore Emulator 確認..."
if curl -sf "http://localhost:8000" --max-time $TIMEOUT &> /dev/null; then
    log_success "Firestore Emulator OK"
else
    log_error "Firestore Emulator 接続失敗"
    OVERALL_STATUS=1
fi

# Auth Emulator確認
log_info "Auth Emulator 確認..."
if curl -sf "http://localhost:9099" --max-time $TIMEOUT &> /dev/null; then
    log_success "Auth Emulator OK"
else
    log_error "Auth Emulator 接続失敗"
    OVERALL_STATUS=1
fi

# Pub/Sub Emulator確認
log_info "Pub/Sub Emulator 確認..."
if curl -sf "http://localhost:8085" --max-time $TIMEOUT &> /dev/null; then
    log_success "Pub/Sub Emulator OK"
else
    log_error "Pub/Sub Emulator 接続失敗"
    OVERALL_STATUS=1
fi

echo ""

# 5. ポート使用状況確認
if $VERBOSE; then
    log_info "🔌 ポート使用状況確認..."
    PORTS=(6379 8080 8000 9099 5001 4000 8085 80)
    for port in "${PORTS[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_success "ポート $port: 使用中"
        else
            log_warning "ポート $port: 未使用"
        fi
    done
    echo ""
fi

# 6. 環境変数確認
if $VERBOSE; then
    log_info "🔧 重要な環境変数確認..."
    if [ -f ".env.development" ]; then
        log_success ".env.development ファイル存在"
    else
        log_warning ".env.development ファイル未存在"
    fi
    
    if [ -f "service-account.json" ]; then
        log_success "service-account.json ファイル存在"
    else
        log_warning "service-account.json ファイル未存在"
    fi
    echo ""
fi

# 7. 統合テスト実行
log_info "🧪 簡易統合テスト実行..."
if command -v curl &> /dev/null; then
    # Analytics Service API テスト
    TEST_ENDPOINT="http://localhost:8080/health"
    if curl -sf "$TEST_ENDPOINT" --max-time $TIMEOUT &> /dev/null; then
        log_success "API エンドポイント テスト OK"
    else
        log_error "API エンドポイント テスト 失敗"
        OVERALL_STATUS=1
    fi
else
    log_warning "curl が利用できないため、API テストをスキップ"
fi

echo ""

# 8. 結果サマリー
log_info "📋 ヘルスチェック結果サマリー"
echo "=================================="

if [ $OVERALL_STATUS -eq 0 ]; then
    log_success "全てのサービスが正常に稼働しています！"
    echo ""
    log_info "🚀 利用可能なエンドポイント:"
    echo "  • Firebase Emulator UI: http://localhost:4000"
    echo "  • Analytics Service:     http://localhost:8080"
    echo "  • Firestore Emulator:    http://localhost:8000"
    echo "  • Auth Emulator:         http://localhost:9099"
    echo "  • Nginx Proxy:           http://localhost:80"
else
    log_error "一部のサービスに問題があります"
    echo ""
    log_info "🔧 トラブルシューティング:"
    echo "  • サービス起動: docker-compose up -d"
    echo "  • ログ確認:     docker-compose logs -f"
    echo "  • サービス再起動: docker-compose restart"
    echo "  • 完全再構築:   docker-compose down -v && docker-compose up --build"
fi

echo ""

# 9. 追加情報（詳細モード）
if $VERBOSE; then
    log_info "📊 システム情報"
    echo "=================="
    echo "ホスト名: $(hostname)"
    echo "OS: $(uname -s)"
    echo "アーキテクチャ: $(uname -m)"
    echo "アップタイム: $(uptime)"
    echo ""
    
    log_info "💾 ディスク使用量"
    echo "=================="
    df -h . | tail -1
    echo ""
    
    log_info "🧠 メモリ使用量"
    echo "=================="
    if command -v free &> /dev/null; then
        free -h
    else
        log_warning "メモリ情報を取得できません"
    fi
    echo ""
fi

exit $OVERALL_STATUS