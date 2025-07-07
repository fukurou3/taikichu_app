# MVP リアルタイム分析サービス用 Dockerfile

FROM python:3.11-slim

# 作業ディレクトリ設定
WORKDIR /app

# システム依存関係
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Python依存関係をコピーしてインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# アプリケーションコードをコピー
COPY main.py .

# 非rootユーザーで実行
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# ポート8080で起動
EXPOSE 8080

# Gunicornで本番運用
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "60", "main:app"]