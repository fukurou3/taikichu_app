# 🩺 Taikichu App - 統合ヘルスチェックスクリプト (PowerShell版)
# ===================================================================

param(
    [switch]$Verbose,
    [int]$Timeout = 5,
    [switch]$Help
)

# 色定義
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"
$Cyan = "Cyan"

# 使用方法表示
function Show-Usage {
    Write-Host ""
    Write-Host "🩺 Taikichu App ヘルスチェック" -ForegroundColor $Blue
    Write-Host "====================================" -ForegroundColor $Blue
    Write-Host ""
    Write-Host "使用方法: .\health-check.ps1 [オプション]"
    Write-Host ""
    Write-Host "オプション:"
    Write-Host "  -Verbose         詳細情報を表示"
    Write-Host "  -Timeout N       タイムアウト時間（秒、デフォルト: 5）"
    Write-Host "  -Help            このヘルプを表示"
    Write-Host ""
    Write-Host "例:"
    Write-Host "  .\health-check.ps1              # 基本ヘルスチェック"
    Write-Host "  .\health-check.ps1 -Verbose     # 詳細モード"
    Write-Host "  .\health-check.ps1 -Timeout 10  # 10秒タイムアウト"
    Write-Host ""
}

# ヘルプが要求された場合
if ($Help) {
    Show-Usage
    exit 0
}

# ログ関数
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor $Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Yellow
}

# ヘルスチェック開始
Write-Host ""
Write-Info "統合ヘルスチェックを開始します..."
Write-Host ""

# 全体の結果を記録
$script:OverallStatus = $true

# 1. Docker環境確認
Write-Info "🐳 Docker 環境確認中..."
try {
    $dockerVersion = docker --version
    if ($dockerVersion) {
        docker info | Out-Null
        Write-Success "Docker 環境 OK"
        if ($Verbose) {
            Write-Host "    Docker Version: $dockerVersion" -ForegroundColor $Cyan
        }
    }
} catch {
    Write-Error "Docker が利用できません"
    $script:OverallStatus = $false
}

# 2. Docker Compose確認
try {
    $composeVersion = docker-compose --version
    if ($composeVersion) {
        Write-Success "Docker Compose OK"
        if ($Verbose) {
            Write-Host "    Docker Compose Version: $composeVersion" -ForegroundColor $Cyan
        }
    }
} catch {
    Write-Error "Docker Compose が利用できません"
    $script:OverallStatus = $false
}

Write-Host ""

# 3. サービス稼働状況確認
Write-Info "📊 サービス稼働状況確認中..."
try {
    $services = docker-compose ps
    if ($services -match "Up") {
        Write-Success "Docker Compose サービス稼働中"
        if ($Verbose) {
            Write-Host ""
            $services | Write-Host
            Write-Host ""
        }
    } else {
        Write-Warning "Docker Compose サービスが起動していません"
        Write-Info "サービスを起動するには: docker-compose up -d"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Docker Compose サービス情報を取得できません"
    $script:OverallStatus = $false
}

Write-Host ""

# 4. 個別サービス確認
Write-Info "🔍 個別サービス確認中..."

# Redis確認
Write-Info "Redis 接続確認..."
try {
    $redisResponse = docker exec taikichu-redis-local redis-cli ping 2>$null
    if ($redisResponse -eq "PONG") {
        Write-Success "Redis 接続 OK"
        if ($Verbose) {
            $redisInfo = docker exec taikichu-redis-local redis-cli INFO stats 2>$null | Select-Object -First 5
            Write-Host "    Redis Stats:" -ForegroundColor $Cyan
            $redisInfo | ForEach-Object { Write-Host "      $_" -ForegroundColor $Cyan }
        }
    } else {
        Write-Error "Redis 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Redis 接続失敗"
    $script:OverallStatus = $false
}

# Analytics Service確認
Write-Info "Analytics Service 確認..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec $Timeout -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Success "Analytics Service OK"
        if ($Verbose) {
            Write-Host "    Response: $($response.Content)" -ForegroundColor $Cyan
        }
    } else {
        Write-Error "Analytics Service 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Analytics Service 接続失敗"
    $script:OverallStatus = $false
}

# Firebase Emulator UI確認
Write-Info "Firebase Emulator UI 確認..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:4000" -TimeoutSec $Timeout -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Success "Firebase Emulator UI OK"
    } else {
        Write-Error "Firebase Emulator UI 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Firebase Emulator UI 接続失敗"
    $script:OverallStatus = $false
}

# Firestore Emulator確認
Write-Info "Firestore Emulator 確認..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8000" -TimeoutSec $Timeout -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Success "Firestore Emulator OK"
    } else {
        Write-Error "Firestore Emulator 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Firestore Emulator 接続失敗"
    $script:OverallStatus = $false
}

# Auth Emulator確認
Write-Info "Auth Emulator 確認..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9099" -TimeoutSec $Timeout -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Success "Auth Emulator OK"
    } else {
        Write-Error "Auth Emulator 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Auth Emulator 接続失敗"
    $script:OverallStatus = $false
}

# Pub/Sub Emulator確認
Write-Info "Pub/Sub Emulator 確認..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8085" -TimeoutSec $Timeout -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Success "Pub/Sub Emulator OK"
    } else {
        Write-Error "Pub/Sub Emulator 応答異常"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "Pub/Sub Emulator 接続失敗"
    $script:OverallStatus = $false
}

Write-Host ""

# 5. ポート使用状況確認
if ($Verbose) {
    Write-Info "🔌 ポート使用状況確認..."
    $ports = @(6379, 8080, 8000, 9099, 5001, 4000, 8085, 80)
    foreach ($port in $ports) {
        try {
            $connection = Test-NetConnection -ComputerName localhost -Port $port -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                Write-Success "ポート $port : 使用中"
            } else {
                Write-Warning "ポート $port : 未使用"
            }
        } catch {
            Write-Warning "ポート $port : 確認不可"
        }
    }
    Write-Host ""
}

# 6. 環境変数確認
if ($Verbose) {
    Write-Info "🔧 重要な環境変数確認..."
    
    if (Test-Path ".env.development") {
        Write-Success ".env.development ファイル存在"
    } else {
        Write-Warning ".env.development ファイル未存在"
    }
    
    if (Test-Path "service-account.json") {
        Write-Success "service-account.json ファイル存在"
    } else {
        Write-Warning "service-account.json ファイル未存在"
    }
    Write-Host ""
}

# 7. 統合テスト実行
Write-Info "🧪 簡易統合テスト実行..."
try {
    $testResponse = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec $Timeout -ErrorAction Stop
    if ($testResponse.StatusCode -eq 200) {
        Write-Success "API エンドポイント テスト OK"
    } else {
        Write-Error "API エンドポイント テスト 失敗"
        $script:OverallStatus = $false
    }
} catch {
    Write-Error "API エンドポイント テスト 失敗"
    $script:OverallStatus = $false
}

Write-Host ""

# 8. 結果サマリー
Write-Info "📋 ヘルスチェック結果サマリー"
Write-Host "=================================="

if ($script:OverallStatus) {
    Write-Success "全てのサービスが正常に稼働しています！"
    Write-Host ""
    Write-Info "🚀 利用可能なエンドポイント:"
    Write-Host "  • Firebase Emulator UI: http://localhost:4000" -ForegroundColor $Cyan
    Write-Host "  • Analytics Service:     http://localhost:8080" -ForegroundColor $Cyan
    Write-Host "  • Firestore Emulator:    http://localhost:8000" -ForegroundColor $Cyan
    Write-Host "  • Auth Emulator:         http://localhost:9099" -ForegroundColor $Cyan
    Write-Host "  • Nginx Proxy:           http://localhost:80" -ForegroundColor $Cyan
} else {
    Write-Error "一部のサービスに問題があります"
    Write-Host ""
    Write-Info "🔧 トラブルシューティング:"
    Write-Host "  • サービス起動: docker-compose up -d" -ForegroundColor $Cyan
    Write-Host "  • ログ確認:     docker-compose logs -f" -ForegroundColor $Cyan
    Write-Host "  • サービス再起動: docker-compose restart" -ForegroundColor $Cyan
    Write-Host "  • 完全再構築:   docker-compose down -v && docker-compose up --build" -ForegroundColor $Cyan
}

Write-Host ""

# 9. 追加情報（詳細モード）
if ($Verbose) {
    Write-Info "📊 システム情報"
    Write-Host "=================="
    Write-Host "ホスト名: $($env:COMPUTERNAME)" -ForegroundColor $Cyan
    Write-Host "OS: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)" -ForegroundColor $Cyan
    Write-Host "アーキテクチャ: $($env:PROCESSOR_ARCHITECTURE)" -ForegroundColor $Cyan
    Write-Host "PowerShell バージョン: $($PSVersionTable.PSVersion)" -ForegroundColor $Cyan
    Write-Host ""
    
    Write-Info "💾 ディスク使用量"
    Write-Host "=================="
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($disk.Size / 1GB, 2)
    $usedGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
    Write-Host "C:ドライブ - 使用済み: ${usedGB}GB / 合計: ${totalGB}GB (空き: ${freeGB}GB)" -ForegroundColor $Cyan
    Write-Host ""
    
    Write-Info "🧠 メモリ使用量"
    Write-Host "=================="
    $memory = Get-CimInstance -ClassName Win32_ComputerSystem
    $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
    Write-Host "合計メモリ: ${totalMemoryGB}GB" -ForegroundColor $Cyan
    Write-Host ""
}

if ($script:OverallStatus) {
    exit 0
} else {
    exit 1
}