# ===== Stage 1: Build Frontend =====
FROM node:20-alpine AS frontend-builder

RUN apk add --no-cache python3 make g++

WORKDIR /app
ARG NPM_REGISTRY=""
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ===== Stage 2: Build Native Addons =====
FROM node:20-alpine AS native-builder

RUN apk add --no-cache python3 make g++

WORKDIR /app
ARG NPM_REGISTRY=""
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ===== Stage 3: Production =====
FROM node:20-alpine AS production

RUN apk add --no-cache \
    python3 \
    py3-pip \
    openssh-client \
    curl \
    xvfb \
    x11vnc \
    ffmpeg \
    xdotool \
    bash

ARG PIP_INDEX_URL=""
RUN if [ -n "$PIP_INDEX_URL" ]; then \
      pip3 install --no-cache-dir --break-system-packages -i "$PIP_INDEX_URL" hermes-agent 2>/dev/null || \
      echo "[WARN] Hermes CLI installation skipped"; \
    else \
      pip3 install --no-cache-dir --break-system-packages hermes-agent 2>/dev/null || \
      echo "[WARN] Hermes CLI installation skipped"; \
    fi && \
    apk del py3-pip && \
    rm -rf /var/cache/apk/*

WORKDIR /app

COPY --from=native-builder /app/node_modules ./node_modules
COPY package.json ./

COPY --from=frontend-builder /app/dist ./dist
COPY server ./server
COPY public ./public
COPY index.html ./
COPY .env .env

RUN mkdir -p /app/data

ENV NODE_ENV=production
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/api/auth/config || exit 1

ENTRYPOINT ["node", "--env-file=.env", "server/index.js"]
