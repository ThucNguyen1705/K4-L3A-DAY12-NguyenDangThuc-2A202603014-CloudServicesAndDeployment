# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production)
#
#   Stage 1 `builder`: cài dependency vào /install
#   Stage 2 `runtime`: chỉ copy /install + source code, chạy bằng user thường
#
# Build:  docker build -t day12-agent:prod .
# Chạy:   docker run --rm -p 8000:8000 -e AGENT_API_KEY=... -e REDIS_URL=... day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ───────────────────────────────────────────────
FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

# Chỉ copy requirements.txt trước: sửa code không làm mất cache layer pip install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ───────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Thư viện đã cài ở builder — không mang theo pip cache hay file tạm
COPY --from=builder /install /usr/local

RUN useradd --create-home --uid 10001 appuser

# Source code copy SAU dependency; chỉ copy đúng thứ app cần.
# Cố ý để file thuộc root: appuser chỉ cần đọc, không sửa được code của app.
COPY app ./app
COPY utils ./utils

USER appuser

EXPOSE 8000

# Gọi đúng cổng app đang nghe ($PORT), urlopen ném lỗi khi /health trả 503
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=4)"]

# `exec` để uvicorn thay chỗ sh làm PID 1 → nhận SIGTERM trực tiếp khi deploy
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
