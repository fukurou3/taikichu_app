# 🐳 ローカル開発環境セットアップガイド

## 📋 前提条件

### 必要なツール
- **Docker Desktop** (Windows/Mac/Linux)
- **Flutter SDK** (3.x以上)
- **Node.js** (18.x以上)
- **Firebase CLI** (`npm install -g firebase-tools`)

### 設定ファイル
- `service-account.json` - Firebase サービスアカウントキー

## 🚀 クイックスタート

### 1. サービスアカウントキー取得
```bash
# Firebase Console → プロジェクト設定 → サービスアカウント
# 「新しい秘密鍵を生成」してダウンロード
# → service-account.json としてプロジェクトルートに配置
```

### 2. Docker環境起動
```bash
# プロジェクトルートで実行
docker-compose up -d

# ログ確認
docker-compose logs -f
```

### 3. 統一パイプライン確認
```bash
# システム健康状態チェック
curl http://localhost:80/health

# Analytics Service確認
curl http://localhost:8080/health

# Redis接続確認
docker exec taikichu-redis-local redis-cli ping
```

### 4. Flutter開発
```bash
# エミュレーター向け設定でFlutter起動
flutter run --dart-define=ENVIRONMENT=development
```

## 🎯 各サービス説明

### Redis (localhost:6379)
- **目的**: 高速データキャッシュ
- **用途**: トレンドスコア、カウンター値、ランキング
- **接続**: `redis-cli -h localhost -p 6379`

### Pub/Sub Emulator (localhost:8085)
- **目的**: イベントメッセージング
- **用途**: 統一パイプラインイベント配信
- **確認**: `curl http://localhost:8085`

### Analytics Service (localhost:8080)
- **目的**: 統一分析処理エンジン
- **API**: 
  - `GET /health` - ヘルスチェック
  - `POST /events` - イベント処理
  - `GET /trend-score/{id}` - トレンドスコア取得
  - `GET /counter/{id}/{type}` - カウンター取得

### Firebase Emulator (localhost:4000)
- **目的**: Firebase サービスローカル実行
- **サービス**:
  - Firestore: localhost:8000
  - Auth: localhost:9099
  - Functions: localhost:5001
- **UI**: http://localhost:4000

## 🔧 開発ワークフロー

### 新機能開発
1. **統一パイプライン使用**: 全データ更新は`UnifiedAnalyticsService`経由
2. **ローカルテスト**: Dockerでフルスタック検証
3. **本番デプロイ**: テスト済みコードのみ

### デバッグ手順
```bash
# 1. Docker状態確認
docker-compose ps

# 2. サービスログ確認
docker-compose logs analytics-service
docker-compose logs pubsub-emulator

# 3. Redis データ確認
docker exec -it taikichu-redis-local redis-cli
> keys *
> get trend_score:countdown_123

# 4. Pub/Sub メッセージ確認
# Firebase Emulator UI → Pub/Sub → analytics-events
```

### トラブルシューティング

#### サービス起動失敗
```bash
# コンテナ再起動
docker-compose restart

# 完全再構築
docker-compose down -v
docker-compose up --build
```

#### ポート競合
```bash
# 使用ポート確認
netstat -an | findstr :8080

# 該当プロセス終了後再起動
docker-compose restart analytics-service
```

#### データリセット
```bash
# Redis データクリア
docker exec taikichu-redis-local redis-cli FLUSHALL

# Firebase Emulator データリセット
firebase emulators:exec --only firestore "echo 'データリセット完了'"
```

## 📊 パフォーマンス監視

### メトリクス取得
```bash
# Analytics Service 統計
curl http://localhost:8080/metrics

# Redis 統計
docker exec taikichu-redis-local redis-cli INFO stats
```

### ベンチマーク
```bash
# 負荷テスト（Apache Bench）
ab -n 1000 -c 10 http://localhost:8080/health
```

## 🔄 統一パイプラインテスト

### イベント送信テスト
```bash
# いいねイベント
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "test_like_123",
    "type": "like_added",
    "countdownId": "test_countdown_1",
    "userId": "test_user_1",
    "timestamp": "2025-01-01T00:00:00Z"
  }'

# レスポンス確認
curl http://localhost:8080/counter/test_countdown_1/likes
```

### エンドツーエンドテスト
```bash
# Flutter統合テスト実行
flutter test integration_test/unified_pipeline_test.dart
```

## 📈 本番環境との差分

| 項目 | ローカル | 本番 |
|------|----------|------|
| Redis | Docker Container | Memorystore |
| Pub/Sub | Emulator | Google Cloud Pub/Sub |
| Analytics | Docker Container | Cloud Run |
| Firestore | Emulator | Production Database |

## 🚨 注意事項

1. **サービスアカウントキー**: `service-account.json`をGitにコミットしない
2. **ポート使用**: 6379, 8080, 8085, 4000, 9099が空いていることを確認
3. **メモリ使用量**: Docker Desktop最低4GB割り当て推奨
4. **本番データ**: ローカル環境では本番データにアクセスしない

## 📞 サポート

問題発生時:
1. `docker-compose logs` でエラー確認
2. `README_ARCHITECTURE.md` で仕様確認
3. GitHub Issues に詳細投稿

---

**ハッピーコーディング！ 🚀**