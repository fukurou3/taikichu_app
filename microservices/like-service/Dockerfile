# いいね専用マイクロサービス - Cloud Run最適化版
FROM python:3.11-slim as builder

RUN useradd --create-home --shell /bin/bash appuser

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 本番イメージ
FROM python:3.11-slim

RUN useradd --create-home --shell /bin/bash appuser

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
COPY --chown=appuser:appuser main.py .

# Cloud Run最適化設定
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

USER appuser

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/health || exit 1

EXPOSE 8080

# 高トラフィック対応（いいね処理は高頻度）
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 4 --threads 2 --worker-class gthread --timeout 60 --preload main:app