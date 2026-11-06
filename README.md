# 🐷 Cofrinho - Gestão Financeira Pessoal & Economia Inteligente

[![Deploy Cofrinho to VPS](https://github.com/lucascorreagoldani/cofrinho/actions/workflows/deploy.yml/badge.svg)](https://github.com/lucascorreagoldani/cofrinho/actions/workflows/deploy.yml)

> O seu copiloto financeiro no iOS: controle seus gastos, estabeleça orçamentos, visualize gráficos analíticos e alcance suas metas de economia com total privacidade.

---

## ✨ Principais Funcionalidades

- **Controle de Gastos e Receitas**: Registro instantâneo (< 3 toques) de despesas e entradas, com seleção de categorias, formas de pagamento (PIX, Cartão, Dinheiro) e notas.
- **Tetos de Gastos & Orçamentos (Budgets)**: Defina quanto você pode gastar no mês geral e por categoria (Alimentação, Moradia, Transporte, Lazer, etc.), recebendo alertas visuais quando o limite se aproxima.
- **Gráficos Analíticos com Swift Charts**:
  - Gráfico Donut de distribuição de despesas por categoria.
  - Gráficos de barras e área com a evolução do fluxo de caixa e histórico mês a mês.
  - Indicadores de saúde financeira e taxa de economia.
- **Cofrinhos de Metas (Savings Goals)**: Crie cofrinhos virtuais para objetivos específicos (ex: Reserva de Emergência, Viagem de Férias, Carro Novo) e acompanhe o progresso de acumulação.
- **Privacidade Absoluta & Offline-First**: Todos os seus dados ficam salvos localmente no seu dispositivo via **SwiftData**, sem necessidade de criar conta e sem envio para servidores de terceiros.
- **Proteção Biométrica**: Bloqueio opcional com **Face ID / Touch ID** para que apenas você acerte seus dados financeiros.
- **Backend Cloud Opcional (Fastify & Redis/Postgres)**: API RESTful moderna com autenticação JWT, invalidação de sessões em Redis (< 1ms) e histórico seguro.

---

## 🛠️ Stack Tecnológica

### Frontend (iOS Native)
- **Linguagem**: Swift 6 (Strict Concurrency ativo).
- **Interface**: SwiftUI moderno (iOS 17+).
- **Persistência**: SwiftData offline-first.
- **Gráficos**: Apple Swift Charts (`SectorMark`, `BarMark`, `AreaMark`, `RuleMark`).
- **Segurança**: LocalAuthentication (`LAContext`).
- **Gerenciador de Projeto**: XcodeGen (`project.yml`).

### Backend & Cloud
- **Runtime & Framework**: Node.js 22 LTS, Fastify 5, Zod 3 (RFC 9457 Problem Details).
- **Cache & Sessões**: Redis 7 Alpine.
- **Banco Relacional**: PostgreSQL 16 Alpine.
- **Containerização**: Docker & Docker Compose.
- **CI/CD**: GitHub Actions com deploy contínuo para VPS (Host Ryzen).

---

## 🐳 Infraestrutura Docker & VPS

O projeto está configurado para conviver harmonicamente na VPS com outros serviços (como o ecossistema KowaMC), garantindo isolamento total de portas:

| Serviço | Porta no Host (VPS) | Porta Default | Motivo da Alteração |
| :--- | :---: | :---: | :--- |
| **Cofrinho API** | `3333` | `3000` | Evita conflito com o Painel Web e Grafana do KowaMC (porta 3000). |
| **Cofrinho Redis** | `6380` | `6379` | Evita conflito com a instância de Redis existente do KowaMC (porta 6379). |
| **Cofrinho Postgres** | `5433` | `5432` | Evita conflito com a instância PostgreSQL do KowaMC (porta 5432). |

> **Nota para Restauração**: Se desejar restaurar qualquer serviço para sua porta padrão posteriormente, edite o mapeamento em `docker-compose.yml` (ex: de `"6380:6379"` para `"6379:6379"`).

---

## 🚀 Como Executar o Projeto

### iOS App
1. Certifique-se de ter o Xcode 15+ ou 16+ instalado e o `xcodegen`:
   ```bash
   brew install xcodegen
   ```
2. Navegue até a pasta `ios`:
   ```bash
   cd cofrinho/ios
   ```
3. Gere o projeto do Xcode:
   ```bash
   xcodegen generate
   ```
4. Abra o projeto no Xcode:
   ```bash
   open Cofrinho.xcodeproj
   ```
5. Execute no Simulador ou no seu iPhone (`Cmd + R`).

### Backend Local
1. Suba o ambiente via Docker Compose:
   ```bash
   docker compose up -d
   ```
2. Ou instale e inicie localmente:
   ```bash
   cd backend
   npm install
   npm run dev
   ```
3. Acesse a documentação Swagger em: `http://localhost:3333/docs` (ou `http://localhost:3000/docs`).
