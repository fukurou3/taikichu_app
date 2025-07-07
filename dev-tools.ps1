# 🐳 Taikichu App - 統一開発環境 PowerShell ツール
# =============================================

param(
    [Parameter(Position=0)]
    [string]$Command = "help"
)

# 色定義
$Yellow = "Yellow"
$Green = "Green"
$Red = "Red"
$Cyan = "Cyan"

function Show-Help {
    Write-Host ""
    Write-Host "🐳 Taikichu App - 統一開発環境" -ForegroundColor $Yellow
    Write-Host "================================" -ForegroundColor $Yellow
    Write-Host ""
    Write-Host "📚 基本コマンド:" -ForegroundColor $Green
    Write-Host "  .\dev-tools.ps1 setup      - 初回セットアップ（環境構築）" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 start      - 全サービス起動" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 stop       - 全サービス停止" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 restart    - 全サービス再起動" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "🔍 監視・デバッグ:" -ForegroundColor $Green
    Write-Host "  .\dev-tools.ps1 logs       - リアルタイムログ表示" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 health     - 全サービス健康状態確認" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 status     - サービス稼働状況表示" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "🧪 開発・テスト:" -ForegroundColor $Green
    Write-Host "  .\dev-tools.ps1 test       - 統合テスト実行" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 migrate    - データ移行実行" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 seed       - テストデータ投入" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "🛠️ メンテナンス:" -ForegroundColor $Green
    Write-Host "  .\dev-tools.ps1 clean      - 全データ・キャッシュクリア" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 rebuild    - 完全再構築" -ForegroundColor $Cyan
    Write-Host "  .\dev-tools.ps1 update     - 依存関係更新" -ForegroundColor $Cyan
    Write-Host ""
}

function Start-Setup {
    Write-Host "🚀 初回セットアップを開始します..." -ForegroundColor $Green
    
    # 環境変数ファイル作成
    if (-Not (Test-Path ".env.development")) {
        Write-Host "📋 環境変数ファイルを作成中..." -ForegroundColor $Yellow
        Copy-Item ".env.example" ".env.development"
        Write-Host "⚠️  .env.development を編集して設定を完了してください" -ForegroundColor $Red
    }
    
    # Docker ビルド
    Write-Host "🐳 Docker イメージをビルド中..." -ForegroundColor $Yellow
    docker-compose build
    
    Write-Host "✅ セットアップ完了！" -ForegroundColor $Green
    Write-Host "次のコマンドでサービスを起動: .\dev-tools.ps1 start" -ForegroundColor $Yellow
}

function Start-Services {
    Write-Host "▶️ 全サービスを起動中..." -ForegroundColor $Green
    docker-compose up -d
    
    Write-Host "🔍 サービス状況確認中..." -ForegroundColor $Yellow
    Start-Sleep -Seconds 5
    Check-Health
}

function Stop-Services {
    Write-Host "⏹️ 全サービスを停止中..." -ForegroundColor $Red
    docker-compose down
}

function Restart-Services {
    Write-Host "🔄 全サービスを再起動中..." -ForegroundColor $Yellow
    docker-compose restart
    Start-Sleep -Seconds 5
    Check-Health
}

function Show-Logs {
    docker-compose logs -f
}

function Check-Health {
    Write-Host "🩺 サービス健康状態を確認中..." -ForegroundColor $Green
    Write-Host ""
    
    Write-Host "📊 Docker コンテナ状況:" -ForegroundColor $Yellow
    docker-compose ps
    Write-Host ""
    
    Write-Host "🔗 エンドポイント確認:" -ForegroundColor $Yellow
    
    # Redis確認
    try {
        $redisResult = docker exec taikichu-redis-local redis-cli ping 2>$null
        if ($redisResult -eq "PONG") {
            Write-Host "✅ Redis OK" -ForegroundColor $Green
        } else {
            Write-Host "❌ Redis ERROR" -ForegroundColor $Red
        }
    } catch {
        Write-Host "❌ Redis ERROR" -ForegroundColor $Red
    }
    
    # Analytics Service確認
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Analytics OK" -ForegroundColor $Green
        } else {
            Write-Host "❌ Analytics ERROR" -ForegroundColor $Red
        }
    } catch {
        Write-Host "❌ Analytics ERROR" -ForegroundColor $Red
    }
    
    # Firebase UI確認
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:4000" -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Firebase UI OK" -ForegroundColor $Green
        } else {
            Write-Host "❌ Firebase UI ERROR" -ForegroundColor $Red
        }
    } catch {
        Write-Host "❌ Firebase UI ERROR" -ForegroundColor $Red
    }
    
    # Pub/Sub Emulator確認
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8085" -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Pub/Sub OK" -ForegroundColor $Green
        } else {
            Write-Host "❌ Pub/Sub ERROR" -ForegroundColor $Red
        }
    } catch {
        Write-Host "❌ Pub/Sub ERROR" -ForegroundColor $Red
    }
}

function Show-Status {
    Write-Host "📊 サービス稼働状況:" -ForegroundColor $Green
    docker-compose ps
}

function Run-Tests {
    Write-Host "🧪 統合テスト実行中..." -ForegroundColor $Green
    
    Write-Host "📋 Flutter テスト:" -ForegroundColor $Yellow
    flutter test
    
    Write-Host "🔗 エンドポイントテスト:" -ForegroundColor $Yellow
    Check-Health
}

function Run-Migration {
    Write-Host "🗃️ データ移行を実行中..." -ForegroundColor $Green
    
    if (-Not (Test-Path "service-account.json")) {
        Write-Host "❌ service-account.json が見つかりません" -ForegroundColor $Red
        Write-Host "Firebase Console からサービスアカウントキーをダウンロードしてください" -ForegroundColor $Yellow
        return
    }
    
    Set-Location migration_scripts
    python firestore_to_redis_migration.py --dry-run
    Set-Location ..
    
    Write-Host "⚠️  dry-run完了。実際の移行には以下を実行:" -ForegroundColor $Yellow
    Write-Host "cd migration_scripts && python firestore_to_redis_migration.py --migrate" -ForegroundColor $Yellow
}

function Seed-Data {
    Write-Host "🌱 テストデータを投入中..." -ForegroundColor $Green
    
    docker exec taikichu-redis-local redis-cli FLUSHALL
    Write-Host "📋 Redis にサンプルデータを投入..." -ForegroundColor $Yellow
    docker exec taikichu-redis-local redis-cli SET trend_score:test_countdown_1 85.5
    docker exec taikichu-redis-local redis-cli HSET counter:test_countdown_1 likes 42 comments 15 participants 128
    
    Write-Host "✅ テストデータ投入完了" -ForegroundColor $Green
}

function Clean-All {
    Write-Host "🧹 全データ・キャッシュをクリア中..." -ForegroundColor $Red
    Write-Host "⚠️  この操作により全てのローカルデータが削除されます" -ForegroundColor $Yellow
    
    $confirm = Read-Host "続行しますか？ (y/N)"
    if ($confirm -eq "y" -or $confirm -eq "Y") {
        docker-compose down -v
        docker system prune -f
        Write-Host "✅ クリア完了" -ForegroundColor $Green
    } else {
        Write-Host "操作をキャンセルしました" -ForegroundColor $Yellow
    }
}

function Rebuild-All {
    Write-Host "🔨 完全再構築中..." -ForegroundColor $Yellow
    docker-compose down -v
    docker-compose build --no-cache
    docker-compose up -d
    Start-Sleep -Seconds 10
    Check-Health
}

function Update-Dependencies {
    Write-Host "📦 依存関係を更新中..." -ForegroundColor $Green
    
    Write-Host "📱 Flutter依存関係:" -ForegroundColor $Yellow
    flutter pub get
    
    Write-Host "🐳 Docker イメージ:" -ForegroundColor $Yellow
    docker-compose pull
    
    Write-Host "✅ 更新完了" -ForegroundColor $Green
}

# メイン処理
switch ($Command.ToLower()) {
    "help" { Show-Help }
    "setup" { Start-Setup }
    "start" { Start-Services }
    "stop" { Stop-Services }
    "restart" { Restart-Services }
    "logs" { Show-Logs }
    "health" { Check-Health }
    "status" { Show-Status }
    "test" { Run-Tests }
    "migrate" { Run-Migration }
    "seed" { Seed-Data }
    "clean" { Clean-All }
    "rebuild" { Rebuild-All }
    "update" { Update-Dependencies }
    default {
        Write-Host "❌ 不明なコマンド: $Command" -ForegroundColor $Red
        Show-Help
    }
}