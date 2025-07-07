#!/bin/bash
# 🐛 Taikichu App - 開発デバッグツール
# ==========================================

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 使用方法表示
show_usage() {
    echo ""
    echo -e "${BLUE}🐛 Taikichu App デバッグツール${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    echo "使用方法: $0 <コマンド> [オプション]"
    echo ""
    echo -e "${GREEN}📋 利用可能なコマンド:${NC}"
    echo "  logs <service>     指定サービスのログを表示"
    echo "  redis-cli          Redis CLIに接続"
    echo "  redis-monitor      Redis コマンド監視"
    echo "  redis-info         Redis 統計情報表示"
    echo "  analytics-test     Analytics Service テスト"
    echo "  firestore-data     Firestore データ確認"
    echo "  pubsub-test        Pub/Sub メッセージテスト"
    echo "  performance        パフォーマンス監視"
    echo "  system-status      システム全体状況確認"
    echo "  cleanup            一時ファイル・ログクリーンアップ"
    echo ""
    echo -e "${GREEN}📋 サービス名:${NC}"
    echo "  redis, analytics-service, firebase-emulator"
    echo "  pubsub-emulator, nginx, migration-service"
    echo ""
    echo -e "${GREEN}💡 使用例:${NC}"
    echo "  $0 logs analytics-service    # Analytics Service ログ"
    echo "  $0 redis-cli                # Redis CLI 起動"
    echo "  $0 analytics-test           # API テスト実行"
    echo "  $0 performance              # パフォーマンス監視"
    echo ""
}

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

# サービスログ表示
show_logs() {
    local service=$1
    if [ -z "$service" ]; then
        log_error "サービス名を指定してください"
        echo "例: $0 logs analytics-service"
        return 1
    fi
    
    log_info "📋 $service のログを表示中..."
    docker-compose logs -f --tail=100 "$service"
}

# Redis CLI接続
redis_cli() {
    log_info "🔗 Redis CLI に接続中..."
    docker exec -it taikichu-redis-local redis-cli
}

# Redis監視
redis_monitor() {
    log_info "👀 Redis コマンド監視開始..."
    log_warning "終了するには Ctrl+C を押してください"
    docker exec -it taikichu-redis-local redis-cli MONITOR
}

# Redis情報表示
redis_info() {
    log_info "📊 Redis 統計情報を取得中..."
    echo ""
    
    echo -e "${CYAN}=== 基本情報 ===${NC}"
    docker exec taikichu-redis-local redis-cli INFO server | grep -E "redis_version|os|arch|uptime"
    echo ""
    
    echo -e "${CYAN}=== メモリ使用量 ===${NC}"
    docker exec taikichu-redis-local redis-cli INFO memory | grep -E "used_memory_human|used_memory_peak_human|maxmemory_human"
    echo ""
    
    echo -e "${CYAN}=== 統計情報 ===${NC}"
    docker exec taikichu-redis-local redis-cli INFO stats | grep -E "total_commands_processed|total_connections_received|keyspace_hits|keyspace_misses"
    echo ""
    
    echo -e "${CYAN}=== データベース情報 ===${NC}"
    docker exec taikichu-redis-local redis-cli INFO keyspace
    echo ""
    
    echo -e "${CYAN}=== サンプルキー (最初の10個) ===${NC}"
    docker exec taikichu-redis-local redis-cli --scan | head -10
    echo ""
}

# Analytics Service テスト
analytics_test() {
    log_info "🧪 Analytics Service テスト実行中..."
    echo ""
    
    # ヘルスチェック
    echo -e "${CYAN}=== ヘルスチェック ===${NC}"
    if curl -sf "http://localhost:8080/health"; then
        log_success "ヘルスチェック OK"
    else
        log_error "ヘルスチェック 失敗"
        return 1
    fi
    echo ""
    
    # システム情報取得
    echo -e "${CYAN}=== システム情報 ===${NC}"
    curl -s "http://localhost:8080/system-info" | python3 -m json.tool 2>/dev/null || curl -s "http://localhost:8080/system-info"
    echo ""
    
    # テストカウンター値取得
    echo -e "${CYAN}=== テストカウンター ===${NC}"
    TEST_ID="test_countdown_1"
    COUNTER_TYPES=("likes" "comments" "participants" "views")
    
    for counter_type in "${COUNTER_TYPES[@]}"; do
        echo -n "$counter_type: "
        curl -s "http://localhost:8080/counter/$TEST_ID/$counter_type" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count', 'N/A'))" 2>/dev/null || echo "N/A"
    done
    echo ""
}

# Firestore データ確認
firestore_data() {
    log_info "🔥 Firestore エミュレーター データ確認中..."
    echo ""
    
    # Firebase CLI が利用可能かチェック
    if ! command -v firebase &> /dev/null; then
        log_error "Firebase CLI がインストールされていません"
        return 1
    fi
    
    echo -e "${CYAN}=== Firestore コレクション一覧 ===${NC}"
    # Firestore エミュレーターが起動している場合のみ
    if curl -sf "http://localhost:8000" &> /dev/null; then
        log_info "Firestore エミュレーター稼働中"
        echo "エミュレーター UI: http://localhost:4000"
    else
        log_warning "Firestore エミュレーターが起動していません"
    fi
    echo ""
}

# Pub/Sub テスト
pubsub_test() {
    log_info "📡 Pub/Sub エミュレーター テスト中..."
    echo ""
    
    # Pub/Sub エミュレーター確認
    if curl -sf "http://localhost:8085" &> /dev/null; then
        log_success "Pub/Sub エミュレーター稼働中"
        
        # テストメッセージ送信
        echo -e "${CYAN}=== テストメッセージ送信 ===${NC}"
        TEST_MESSAGE='{"eventId":"debug_test","type":"test","countdownId":"debug_countdown","userId":"debug_user","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
        
        echo "送信メッセージ: $TEST_MESSAGE"
        
        # Analytics Service 経由でテスト
        curl -X POST "http://localhost:8080/events" \
             -H "Content-Type: application/json" \
             -d "$TEST_MESSAGE" 2>/dev/null && log_success "メッセージ送信完了" || log_error "メッセージ送信失敗"
    else
        log_error "Pub/Sub エミュレーターが起動していません"
    fi
    echo ""
}

# パフォーマンス監視
performance_monitoring() {
    log_info "📈 パフォーマンス監視開始..."
    echo ""
    
    # Docker コンテナ リソース使用量
    echo -e "${CYAN}=== Docker コンテナ リソース使用量 ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo ""
    
    # Analytics Service 負荷テスト
    echo -e "${CYAN}=== Analytics Service 負荷テスト ===${NC}"
    if command -v ab &> /dev/null; then
        log_info "Apache Bench で負荷テスト実行中..."
        ab -n 100 -c 5 -q "http://localhost:8080/health"
    else
        log_warning "Apache Bench (ab) がインストールされていません"
        
        # 代替: curlでの簡易テスト
        log_info "curl での簡易パフォーマンステスト..."
        for i in {1..5}; do
            echo -n "Test $i: "
            time curl -sf "http://localhost:8080/health" > /dev/null && echo "OK" || echo "FAIL"
        done
    fi
    echo ""
    
    # Redis パフォーマンス
    echo -e "${CYAN}=== Redis パフォーマンス ===${NC}"
    docker exec taikichu-redis-local redis-cli --latency-history -i 1 2>/dev/null &
    REDIS_PID=$!
    sleep 5
    kill $REDIS_PID 2>/dev/null
    echo ""
}

# システム全体状況
system_status() {
    log_info "🖥️ システム全体状況確認中..."
    echo ""
    
    # Docker 環境状況
    echo -e "${CYAN}=== Docker 環境 ===${NC}"
    echo "Docker Version: $(docker --version)"
    echo "Docker Compose Version: $(docker-compose --version)"
    echo "稼働コンテナ数: $(docker ps -q | wc -l)"
    echo ""
    
    # ディスク使用量
    echo -e "${CYAN}=== ディスク使用量 ===${NC}"
    df -h . | tail -1
    echo ""
    
    # Docker イメージ・ボリューム使用量
    echo -e "${CYAN}=== Docker リソース使用量 ===${NC}"
    docker system df
    echo ""
    
    # ネットワーク接続
    echo -e "${CYAN}=== 重要ポート使用状況 ===${NC}"
    PORTS=(6379 8080 8000 9099 5001 4000 8085 80)
    for port in "${PORTS[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "ポート $port: ✅ 使用中"
        else
            echo "ポート $port: ❌ 未使用"
        fi
    done
    echo ""
}

# クリーンアップ
cleanup() {
    log_info "🧹 クリーンアップ実行中..."
    echo ""
    
    # Docker ログクリーンアップ
    echo -e "${CYAN}=== Docker ログクリーンアップ ===${NC}"
    docker system prune -f --volumes
    log_success "Docker 一時ファイルクリーンアップ完了"
    
    # アプリケーションログクリーンアップ
    echo -e "${CYAN}=== アプリケーションログクリーンアップ ===${NC}"
    find . -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    find . -name "migration_*.log" -type f -delete 2>/dev/null || true
    log_success "古いログファイルクリーンアップ完了"
    
    # Redis データクリーンアップ（開発環境のみ）
    echo -e "${CYAN}=== Redis テストデータクリーンアップ ===${NC}"
    docker exec taikichu-redis-local redis-cli FLUSHDB > /dev/null 2>&1
    log_success "Redis テストデータクリーンアップ完了"
    
    echo ""
    log_success "全クリーンアップ完了"
}

# メイン処理
case "$1" in
    "logs")
        show_logs "$2"
        ;;
    "redis-cli")
        redis_cli
        ;;
    "redis-monitor")
        redis_monitor
        ;;
    "redis-info")
        redis_info
        ;;
    "analytics-test")
        analytics_test
        ;;
    "firestore-data")
        firestore_data
        ;;
    "pubsub-test")
        pubsub_test
        ;;
    "performance")
        performance_monitoring
        ;;
    "system-status")
        system_status
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|"--help"|"-h"|"")
        show_usage
        ;;
    *)
        log_error "不明なコマンド: $1"
        show_usage
        exit 1
        ;;
esac