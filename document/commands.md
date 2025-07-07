# 🚀 Taikichu App 開発コマンド集

## 📋 クイックリファレンス

| 操作 | コマンド |
|------|----------|
| 🚀 環境起動 | `docker-compose up -d` |
| 🛑 環境停止 | `docker-compose down` |
| 🩺 ヘルスチェック | `curl http://localhost:8080/health` |
| 📱 Flutter起動 | `flutter run --dart-define=ENVIRONMENT=development` |
| 🔍 ログ確認 | `docker-compose logs -f analytics-service` |

## 🐳 Docker環境管理

```powershell
# 基本操作
docker-compose up -d                    # 全サービス起動
docker-compose down                     # 全サービス停止  
docker-compose ps                       # サービス状況確認
docker-compose restart analytics-service # 特定サービス再起動

# ログ確認
docker-compose logs -f                  # 全ログ表示
docker-compose logs analytics-service   # 特定サービスログ

# トラブルシューティング
docker-compose down -v && docker-compose up --build -d  # 完全再構築
docker-compose kill analytics-service && docker-compose up -d analytics-service  # 強制再起動
```

## 🩺 ヘルスチェック

```bash
# クイックチェック
curl http://localhost:8080/health       # Analytics Service
docker exec taikichu-redis-local redis-cli ping  # Redis
curl http://localhost:8085              # Pub/Sub Emulator

# 詳細診断
./scripts/health-check.sh -v            # Unix系
./scripts/health-check.ps1 -Verbose     # PowerShell
```

## 📱 Flutter開発

```bash
# アプリ起動
flutter run --dart-define=ENVIRONMENT=development  # 開発環境
flutter run -d chrome                              # Chrome起動
flutter run -d windows                             # Windows起動

# テスト・ビルド
flutter test                                       # 全テスト実行
flutter test test/countdown_search_test.dart       # 特定テスト
flutter build apk --debug                          # Android Debug
flutter build windows --release                    # Windows Release
```

## 📊 データ操作・API

```bash
# Redis操作
docker exec -it taikichu-redis-local redis-cli     # CLI接続
docker exec taikichu-redis-local redis-cli keys "*"  # 全キー確認
docker exec taikichu-redis-local redis-cli FLUSHALL # データクリア

# Analytics API テスト
curl http://localhost:8080/trend-score/countdown_123     # トレンドスコア
curl http://localhost:8080/counter/countdown_123/likes   # カウンター

# イベント送信
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -d '{"eventId":"test_123","type":"like_added","countdownId":"test_1","userId":"user_1"}'
```

## 🔧 開発ツール

```powershell
# PowerShell 自動化ツール
./dev-tools.ps1 setup     # 初回セットアップ
./dev-tools.ps1 start     # 環境起動
./dev-tools.ps1 health    # ヘルスチェック
./dev-tools.ps1 logs      # ログ確認
./dev-tools.ps1 clean     # クリーンアップ

# VS Code タスク (Ctrl+Shift+P → "Tasks: Run Task")
- 🐳 Docker: 全サービス起動
- 📱 Flutter: アプリ起動  
- 🩺 ヘルスチェック実行
```

## 🗃️ データ移行・本番連携

```bash
# データ移行 (必要時のみ)
python migration_scripts/firestore_to_redis_migration.py --dry-run  # ドライラン
python migration_scripts/firestore_to_redis_migration.py --migrate  # 実行

# Firebase 本番操作
firebase login                          # ログイン
firebase deploy --only functions        # Functions デプロイ
firebase deploy --only firestore:rules  # ルールデプロイ
```

## 🧹 メンテナンス・監視

```bash
# パフォーマンス監視
curl http://localhost:8080/metrics                      # Analytics メトリクス
docker exec taikichu-redis-local redis-cli INFO stats  # Redis統計
docker stats                                            # リソース使用量

# クリーンアップ
docker system prune -f                   # Docker クリーンアップ
docker exec taikichu-redis-local redis-cli FLUSHALL  # Redis データクリア
```

## 🚨 トラブルシューティング

```bash
# ポート競合解決
netstat -an | findstr :8080             # ポート使用確認
taskkill /PID <プロセスID> /F          # プロセス終了

# サービス復旧
docker-compose down --remove-orphans    # 緊急停止
docker-compose up -d --force-recreate   # 強制再起動

# 認証確認
Get-Content service-account.json | ConvertFrom-Json | Select-Object client_email
```

---

## 📋 日常開発フロー

```bash
# 1️⃣ 開発開始
docker-compose up -d                                    # 環境起動
curl http://localhost:8080/health                       # 動作確認
flutter run --dart-define=ENVIRONMENT=development      # Flutter起動

# 2️⃣ 開発中
docker-compose logs -f analytics-service                # ログ監視
curl http://localhost:8080/events -X POST -d '...'     # API テスト

# 3️⃣ 開発終了  
docker-compose down                                     # 環境停止
```

**ハッピーコーディング！** 🎉