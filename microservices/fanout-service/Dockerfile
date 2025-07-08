# ファンアウト専用マイクロサービス - Cloud Run最適化版
FROM python:3.11-slim as builder

# セキュリティ強化: 非rootユーザー作成
RUN useradd --create-home --shell /bin/bash appuser

# システム依存関係の最小化
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# 依存関係のインストール
WORKDIR /app
COPY requirements.txt .

# 仮想環境で依存関係を分離
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 本番イメージ
FROM python:3.11-slim

# 非rootユーザーでの実行
RUN useradd --create-home --shell /bin/bash appuser

# 仮想環境とアプリケーションコードをコピー
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
COPY --chown=appuser:appuser main.py .

# Cloud Run最適化設定
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# セキュリティ: 非特権ユーザーで実行
USER appuser

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/health || exit 1

# Cloud Run標準ポート
EXPOSE 8080

# Gunicorn起動（本番環境向け）
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 2 --threads 4 --worker-class gthread --timeout 120 --preload main:app