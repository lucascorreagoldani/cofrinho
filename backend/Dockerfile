# =============================================================================
# COFRINHO API - RUNNER DE PRODUÇÃO (Node.js 22 Alpine)
# =============================================================================
FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production

# Dependências de produção pré-compiladas e podadas pelo CI/CD
COPY package*.json ./
COPY node_modules ./node_modules

# Artefatos compilados e esquemas SQL
COPY dist ./dist
COPY src/database/schema.sql ./dist/database/schema.sql

EXPOSE 3000

CMD ["node", "dist/server.js"]
