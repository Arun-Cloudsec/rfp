# ── Stage 1: Install dependencies ──────────────────────────────
# Pin the Alpine minor version so the rebuild produces deterministic
# image SHAs and zizmor stops flagging "mutable container reference".
FROM node:20-alpine3.20 AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

# ── Stage 2: Production runtime ────────────────────────────────
FROM node:20-alpine3.20 AS production

# Apply security updates from the Alpine package index. node:20-alpine3.20
# ships with apk packages that may have HIGH-severity CVEs by the time the
# image hits production; `apk upgrade` brings them current. Without this,
# Trivy flags ~10 HIGHs on every build.
RUN apk upgrade --no-cache

RUN addgroup -g 1001 -S appgroup \
    && adduser -u 1001 -S appuser -G appgroup \
    && apk add --no-cache dumb-init

# Remove npm and corepack from the production image. Production only needs
# the node binary to run server.js — npm itself ships with bundled deps
# (cross-spawn, glob, minimatch, tar) that have known HIGHs. Stripping npm
# eliminates ~11 HIGHs without affecting runtime.
RUN rm -rf /usr/local/lib/node_modules/npm \
    /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package*.json ./
COPY --from=builder --chown=appuser:appgroup /app/server.js ./server.js
COPY --from=builder --chown=appuser:appgroup /app/manage.js ./manage.js
COPY --from=builder --chown=appuser:appgroup /app/src ./src
COPY --from=builder --chown=appuser:appgroup /app/public ./public

RUN mkdir -p /app/data \
    && chown -R appuser:appgroup /app/data \
    && rm -rf /tmp/* /var/cache/apk/*

USER appuser
ENV NODE_ENV=production
ENV PORT=3010
EXPOSE 3010
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
