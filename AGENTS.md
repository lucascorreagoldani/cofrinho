# Cofrinho Project - Agent Guidelines & Context

This repository contains the `Cofrinho` project ("O seu copiloto de finanças pessoais, orçamentos e economia inteligente").
Development includes **100% Native iOS First** (Swift & SwiftUI) targeting iOS 17+ with Swift 6 strict concurrency, and a high-performance **Cloud Backend** (Fastify, PostgreSQL 16, Redis 7) with continuous deployment to a dedicated VPS.

## Guidelines & Rules

All code and design contributions must follow:
1. [Swift Guidelines](file:///Users/lucas/Documents/Develop/KowaMC/cofrinho/.agents/rules/swift-guidelines.md)
2. [iOS Cofrinho Standards](file:///Users/lucas/Documents/Develop/KowaMC/cofrinho/.agents/rules/ios-cofrinho-standards.md)
3. Available Skills in `.agents/skills/`:
   - **Backend & Cloud**:
     - `cofrinho-redis`: Namespaces (`cofrinho:*`), session cache (<1ms), numeric epoch ms timestamps, TTLs, non-blocking circuit breaker, Docker mapping `6380:6379`.
     - `cofrinho-postgres`: Incremental IDs (`BIGSERIAL` 1, 2, 3...), numeric timestamps (`BIGINT`), connection pooling, safe transactions (`BEGIN`/`COMMIT`/`ROLLBACK`), `log_errors` auditing, Docker mapping `5433:5432`.
   - **iOS Native**:
     - `swift-charts`, `swiftdata`, `financekit`, `widgetkit`, `swift-formatstyle`, `swift-concurrency`, `swiftui-patterns`, `swiftui-layout-components`, `swiftui-gestures`, `swiftui-animation`, `ios-localization`, `swift-security`.

## Canonical Architectural Standards

### 1. Incremental IDs & Numeric Timestamps
- **User IDs**: Incremental integer (`BIGSERIAL PRIMARY KEY` in Postgres, `number` in TypeScript: 1, 2, 3...).
- **Timestamps**: Stored strictly as numeric Unix epoch milliseconds (`BIGINT` in Postgres, `number` / `Date.now()` in TypeScript and Redis). ISO date strings (`TIMESTAMPTZ`) are eliminated from database storage.

### 2. Error & Incident Architecture
- **RFC 9457 Problem Details**: Standardized error responses with `type`, `title`, `status`, `detail`, `code`, `incidentId`, and `timestamp`.
- **ErrorAuditor**: Centralized auditor persisting critical exceptions into the PostgreSQL `log_errors` table with stack traces and context payloads, returning an actionable `incidentId` ticket for client support.
- **Single-Line Comments Rule**: In Java/TypeScript, single-line comments (`//`) are strictly prohibited. Always use block comments (`/* ... */`) or Javadoc (`/** ... */`).

### 3. Docker & VPS Ports Topology
- **API**: Host port `3333` -> Container `3000` (Default: `3000`).
- **PostgreSQL**: Host port `5433` -> Container `5432` (Default: `5432`).
- **Redis**: Host port `6380` -> Container `6379` (Default: `6379`).

## Xcode MCP Integration
The project uses Apple's official `xcrun mcpbridge`:
- `DocumentationSearch`: Consultar documentação oficial de APIs Apple antes de codificar.
- `BuildProject`: Validar compilação do projeto no Xcode.
- `GetBuildLog`: Obter diagnósticos estruturados de erros.
- `RenderPreview`: Renderizar e inspecionar previews SwiftUI.
