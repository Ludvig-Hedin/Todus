# ========================================
# Dependencies Stage: Install Dependencies
# ========================================
FROM node:22-alpine AS deps
WORKDIR /app

RUN npm install -g bun@1.3.10

# Copy workspace configuration and package files
COPY package.json bun.lock turbo.json ./
COPY apps/server/package.json ./apps/server/
COPY packages/ ./packages/
COPY patches/ ./patches/

# Install dependencies needed for migrations
RUN bun install --frozen-lockfile

# ========================================
# Runner Stage: Production Environment
# ========================================
FROM node:22-alpine AS runner
WORKDIR /app

RUN npm install -g bun@1.3.10

# Copy workspace configuration and dependencies
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY --from=deps /app/bun.lock ./bun.lock

# Copy server app with database configuration
COPY apps/server/ ./apps/server/
COPY packages/ ./packages/

WORKDIR /app/apps/server
