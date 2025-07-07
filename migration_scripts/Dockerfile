# データ移行サービス用 Dockerfile
FROM python:3.11-slim

# 作業ディレクトリ設定
WORKDIR /app

# システム依存関係
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Python依存関係をコピーしてインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 移行スクリプトをコピー
COPY firestore_to_redis_migration.py .
COPY README.md .

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import redis; r=redis.Redis(host='redis', port=6379); r.ping()" || exit 1

# 非rootユーザーで実行
RUN adduser --disabled-password --gecos '' migrationuser
USER migrationuser

# デフォルトコマンド
CMD ["tail", "-f", "/dev/null"]