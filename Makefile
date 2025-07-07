# 🐳 Taikichu App - 統一開発環境 Makefile
# =============================================

.PHONY: help setup start stop restart logs clean health test build deploy

# デフォルトターゲット
.DEFAULT_GOAL := help

# 色付きヘルプメッセージ
YELLOW := \033[33m
GREEN := \033[32m
RED := \033[31m
NC := \033[0m # No Color

## 📋 ヘルプ表示
help:
	@echo ""
	@echo "$(YELLOW)🐳 Taikichu App - 統一開発環境$(NC)"
	@echo "$(YELLOW)================================$(NC)"
	@echo ""
	@echo "$(GREEN)📚 基本コマンド:$(NC)"
	@echo "  $(YELLOW)make setup$(NC)      - 初回セットアップ（環境構築）"
	@echo "  $(YELLOW)make start$(NC)      - 全サービス起動"
	@echo "  $(YELLOW)make stop$(NC)       - 全サービス停止"
	@echo "  $(YELLOW)make restart$(NC)    - 全サービス再起動"
	@echo ""
	@echo "$(GREEN)🔍 監視・デバッグ:$(NC)"
	@echo "  $(YELLOW)make logs$(NC)       - リアルタイムログ表示"
	@echo "  $(YELLOW)make health$(NC)     - 全サービス健康状態確認"
	@echo "  $(YELLOW)make status$(NC)     - サービス稼働状況表示"
	@echo ""
	@echo "$(GREEN)🧪 開発・テスト:$(NC)"
	@echo "  $(YELLOW)make test$(NC)       - 統合テスト実行"
	@echo "  $(YELLOW)make migrate$(NC)    - データ移行実行"
	@echo "  $(YELLOW)make seed$(NC)       - テストデータ投入"
	@echo ""
	@echo "$(GREEN)🛠️ メンテナンス:$(NC)"
	@echo "  $(YELLOW)make clean$(NC)      - 全データ・キャッシュクリア"
	@echo "  $(YELLOW)make rebuild$(NC)    - 完全再構築"
	@echo "  $(YELLOW)make update$(NC)     - 依存関係更新"
	@echo ""

## 🚀 初回セットアップ
setup:
	@echo "$(GREEN)🚀 初回セットアップを開始します...$(NC)"
	@if [ ! -f .env.development ]; then \
		echo "$(YELLOW)📋 環境変数ファイルを作成中...$(NC)"; \
		cp .env.example .env.development; \
		echo "$(RED)⚠️  .env.development を編集して設定を完了してください$(NC)"; \
	fi
	@echo "$(YELLOW)🐳 Docker イメージをビルド中...$(NC)"
	docker-compose build
	@echo "$(GREEN)✅ セットアップ完了！$(NC)"
	@echo "$(YELLOW)次のコマンドでサービスを起動: make start$(NC)"

## ▶️ 全サービス起動
start:
	@echo "$(GREEN)▶️ 全サービスを起動中...$(NC)"
	docker-compose up -d
	@echo "$(YELLOW)🔍 サービス状況確認中...$(NC)"
	@sleep 5
	@make health

## ⏹️ 全サービス停止
stop:
	@echo "$(RED)⏹️ 全サービスを停止中...$(NC)"
	docker-compose down

## 🔄 全サービス再起動
restart:
	@echo "$(YELLOW)🔄 全サービスを再起動中...$(NC)"
	docker-compose restart
	@sleep 5
	@make health

## 📋 リアルタイムログ表示
logs:
	docker-compose logs -f

## 🩺 全サービス健康状態確認
health:
	@echo "$(GREEN)🩺 サービス健康状態を確認中...$(NC)"
	@echo ""
	@echo "$(YELLOW)📊 Docker コンテナ状況:$(NC)"
	@docker-compose ps
	@echo ""
	@echo "$(YELLOW)🔗 エンドポイント確認:$(NC)"
	@echo "Redis接続:" && docker exec taikichu-redis-local redis-cli ping 2>/dev/null && echo "$(GREEN)✅ Redis OK$(NC)" || echo "$(RED)❌ Redis ERROR$(NC)"
	@echo "Analytics Service:" && curl -sf http://localhost:8080/health >/dev/null && echo "$(GREEN)✅ Analytics OK$(NC)" || echo "$(RED)❌ Analytics ERROR$(NC)"
	@echo "Firebase UI:" && curl -sf http://localhost:4000 >/dev/null && echo "$(GREEN)✅ Firebase UI OK$(NC)" || echo "$(RED)❌ Firebase UI ERROR$(NC)"
	@echo "Pub/Sub Emulator:" && curl -sf http://localhost:8085 >/dev/null && echo "$(GREEN)✅ Pub/Sub OK$(NC)" || echo "$(RED)❌ Pub/Sub ERROR$(NC)"

## 📊 サービス稼働状況表示
status:
	@echo "$(GREEN)📊 サービス稼働状況:$(NC)"
	docker-compose ps

## 🧪 統合テスト実行
test:
	@echo "$(GREEN)🧪 統合テスト実行中...$(NC)"
	@echo "$(YELLOW)📋 Flutter テスト:$(NC)"
	flutter test
	@echo "$(YELLOW)🔗 エンドポイントテスト:$(NC)"
	@make health

## 🗃️ データ移行実行
migrate:
	@echo "$(GREEN)🗃️ データ移行を実行中...$(NC)"
	@if [ ! -f service-account.json ]; then \
		echo "$(RED)❌ service-account.json が見つかりません$(NC)"; \
		echo "$(YELLOW)Firebase Console からサービスアカウントキーをダウンロードしてください$(NC)"; \
		exit 1; \
	fi
	cd migration_scripts && python firestore_to_redis_migration.py --dry-run
	@echo "$(YELLOW)⚠️  dry-run完了。実際の移行には以下を実行:$(NC)"
	@echo "$(YELLOW)cd migration_scripts && python firestore_to_redis_migration.py --migrate$(NC)"

## 🌱 テストデータ投入
seed:
	@echo "$(GREEN)🌱 テストデータを投入中...$(NC)"
	docker exec taikichu-redis-local redis-cli FLUSHALL
	@echo "$(YELLOW)📋 Redis にサンプルデータを投入...$(NC)"
	docker exec taikichu-redis-local redis-cli SET trend_score:test_countdown_1 85.5
	docker exec taikichu-redis-local redis-cli HSET counter:test_countdown_1 likes 42 comments 15 participants 128
	@echo "$(GREEN)✅ テストデータ投入完了$(NC)"

## 🧹 全データ・キャッシュクリア
clean:
	@echo "$(RED)🧹 全データ・キャッシュをクリア中...$(NC)"
	@echo "$(YELLOW)⚠️  この操作により全てのローカルデータが削除されます$(NC)"
	@read -p "続行しますか？ (y/N): " confirm && [ "$$confirm" = "y" ]
	docker-compose down -v
	docker system prune -f
	@echo "$(GREEN)✅ クリア完了$(NC)"

## 🔨 完全再構築
rebuild:
	@echo "$(YELLOW)🔨 完全再構築中...$(NC)"
	docker-compose down -v
	docker-compose build --no-cache
	docker-compose up -d
	@sleep 10
	@make health

## 📦 依存関係更新
update:
	@echo "$(GREEN)📦 依存関係を更新中...$(NC)"
	@echo "$(YELLOW)📱 Flutter依存関係:$(NC)"
	flutter pub get
	@echo "$(YELLOW)🐳 Docker イメージ:$(NC)"
	docker-compose pull
	@echo "$(GREEN)✅ 更新完了$(NC)"

## 🚢 本番デプロイ準備
deploy-prepare:
	@echo "$(GREEN)🚢 本番デプロイ準備中...$(NC)"
	@echo "$(YELLOW)🧪 テスト実行:$(NC)"
	@make test
	@echo "$(YELLOW)🔍 品質チェック:$(NC)"
	flutter analyze
	@echo "$(YELLOW)🏗️ ビルド確認:$(NC)"
	flutter build apk --debug
	@echo "$(GREEN)✅ デプロイ準備完了$(NC)"