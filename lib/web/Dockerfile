# Stage 1: Build Flutter web
FROM ghcr.io/flutter/flutter:3.41.4 AS builder

WORKDIR /app

# Copy pubspec files for dependency caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy source code
COPY lib/ ./lib/
COPY assets/ ./assets/
COPY config/ ./config/
COPY web/ ./web/

# Build Flutter web
RUN flutter build web --release

# Stage 2: Serve with Caddy
FROM caddy:2-alpine

WORKDIR /app

# Copy built web assets from builder
COPY --from=builder /app/build/web ./public

# Copy Caddyfile
COPY lib/web/Caddyfile ./Caddyfile

# Expose port
EXPOSE 8080

# Start Caddy
CMD ["caddy", "run", "--config", "Caddyfile", "--adapter", "caddyfile"]
