# =============================================================================
# COFRINHO API - DOCKERFILE (Node.js 22 Alpine)
# =============================================================================

# Estágio 1: Build da Aplicação TypeScript
FROM node:22-alpine AS builder

WORKDIR /app

# Instala dependências completas para o build
COPY package*.json tsconfig.json ./
RUN npm ci

# Copia código-fonte e compila com tsup
COPY src/ ./src/
RUN npm run build

# Estágio 2: Imagem Leve de Execução (Runner)
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# Instala apenas dependências de produção
COPY package*.json ./
RUN npm ci --omit=dev

# Copia build compilado e esquemas SQL
COPY --from=builder /app/dist ./dist
COPY src/database/schema.sql ./dist/database/schema.sql
COPY src/database/schema.sql ./src/database/schema.sql

# Porta padrão interna da aplicação
EXPOSE 3000

# Inicializa o servidor Fastify
CMD ["node", "dist/server.js"]
