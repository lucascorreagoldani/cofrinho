# Cofrinho Project - Agent Guidelines & Context

This repository contains the `Cofrinho` project ("O seu copiloto de finanças pessoais, orçamentos e economia inteligente").
Development includes **100% Native iOS First** (Swift & SwiftUI) targeting iOS 17+ with Swift 6 strict concurrency, and a high-performance **Cloud Backend** (Fastify, PostgreSQL 16, Redis 7) with continuous deployment to a dedicated VPS.

## Guidelines & Rules

All code and design contributions must follow:
1. [Swift Guidelines](file:///Users/lucas/Documents/Develop/cofrinho/.agents/rules/swift-guidelines.md)
2. [iOS Cofrinho Standards](file:///Users/lucas/Documents/Develop/cofrinho/.agents/rules/ios-cofrinho-standards.md)
3. Available Skills in `.agents/skills/`:
   - **Backend & Cloud**:
     - `cofrinho-redis`: Namespaces (`cofrinho:*`), session cache (<1ms), numeric epoch ms timestamps, TTLs, synchronous `SCAN + PIPELINE DEL` invalidation, non-blocking circuit breaker, Docker mapping `6380:6379`.
     - `cofrinho-postgres`: Incremental IDs (`BIGSERIAL` 1, 2, 3...), numeric timestamps (`BIGINT`), PK/FK referential integrity, connection pooling, safe transactions (`BEGIN`/`COMMIT`/`ROLLBACK`), audit trail (`created_by_user_id`, `updated_by_user_id`, `transaction_modifications`), `log_errors` auditing, Docker mapping `5433:5432`.
   - **iOS Native**:
     - `swift-charts`, `swiftdata`, `financekit`, `widgetkit`, `swift-formatstyle`, `swift-concurrency`, `swiftui-patterns`, `swiftui-layout-components`, `swiftui-gestures`, `swiftui-animation`, `ios-localization`, `swift-security`.

## Canonical Architectural Standards

### 1. Incremental IDs & Numeric Timestamps
- **Entity IDs**: Incremental integer (`BIGSERIAL PRIMARY KEY` in Postgres, `number` in TypeScript: 1, 2, 3...) across `users`, `categories`, `accounts`, `transactions`, `transaction_modifications`, `budgets`, and `goals`.
- **Timestamps**: Stored strictly as numeric Unix epoch milliseconds (`BIGINT` in Postgres, `number` / `Date.now()` in TypeScript and Redis). ISO date strings (`TIMESTAMPTZ`) are eliminated from database storage.

### 2. Public API vs. Private API & Enum-Driven User Autonomy
- **API Pública (`/v1/public/*`)**: Unauthenticated endpoints (`GET /v1/public/status`, `GET /v1/public/enums`, `GET /v1/public/time`) cached in Redis (`cofrinho:public:enums`), serving canonical system ENUMs (`record_status`, `transaction_filter_status`, `transaction_type`, `account_type`, `delete_cascade_mode`, `session_status`, `error_log_status`), personalization catalogs (`category_icons`, `account_icons`, `colors`), and server health/time telemetry.
- **API Privada (`/v1/*`)**: Session/Bearer authenticated endpoints strictly scoped by `user_id` (`REFERENCES users(id)`), exposing full CRUD with validation and per-user Redis cache invalidation for `transactions`, `categories`, `accounts`, `users/preferences` (including `default_transaction_type`), budgets, and goals.
- **iOS Navigation Hub (`Início`)**: Bottom `TabView` organizes the 5 canonical tabs (`Início | Extrato | Lançamento | Objetivos | Perfil`), where `HomeHubView` delivers instant balance, one-time per-account `?` onboarding suggestion (`RECEITA`/`GASTO` deep links), quick modal launch sheet, `Swift Charts` income vs. expense comparison, and live preference updates (`default_transaction_type`) without app restart.
- **POO, SOLID & Autonomy**: Domain types follow strong ENUM contracts while allowing users full customization and CRUD autonomy over their personal categories, accounts, colors, icons, and launch defaults.

### 3. Audit Trail & Visual Privacy Standards
- **Creator & Modifier Tracking**: `transactions` records both `created_by_user_id` / `created_at` and `updated_by_user_id` / `updated_at`, plus immutable edit history in `transaction_modifications`.
- **`@username`-Only Exposure**: Audit responses (`created_by`, `updated_by`) expose `{ id, username }` without email addresses; the iOS UI displays strictly `@username`.
- **Global UI Semantic Colors (iOS)**: **Editar** actions MUST always use **Orange (`Color.orange`)**; **Excluir / Apagar** actions MUST always use **Red (`Color.red`)** across swipe actions, menus, and management views.

### 4. Error & Incident Architecture
- **RFC 9457 Problem Details**: Standardized error responses with `type`, `title`, `status`, `detail`, `code`, `incidentId`, and `timestamp`.
- **ErrorAuditor**: Centralized auditor persisting critical exceptions into the PostgreSQL `log_errors` table with stack traces and context payloads, returning an actionable `incidentId` ticket for client support.
- **Single-Line Comments Rule**: In Java/TypeScript, single-line comments (`//`) are strictly prohibited. Always use block comments (`/* ... */`) or Javadoc (`/** ... */`).

### 5. Docker & VPS Ports Topology
- **API**: Host port `3333` -> Container `3000` (Default: `3000`).
- **PostgreSQL**: Host port `5433` -> Container `5432` (Default: `5432`).
- **Redis**: Host port `6380` -> Container `6379` (Default: `6379`).

## Xcode MCP Integration
The project uses Apple's official `xcrun mcpbridge`:
- `DocumentationSearch`: Consultar documentação oficial de APIs Apple antes de codificar.
- `BuildProject`: Validar compilação do projeto no Xcode.
- `GetBuildLog`: Obter diagnósticos estruturados de erros.
- `RenderPreview`: Renderizar e inspecionar previews SwiftUI.
