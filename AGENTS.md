# Cofrinho Project - Agent Guidelines & Context

This repository contains the `Cofrinho` project ("O seu copiloto de finanças pessoais, orçamentos e economia inteligente").
Development priority is **100% Native iOS First** (Swift & SwiftUI) targeting iOS 17+ with Swift 6 strict concurrency, followed by widgets, watchOS extension, and local biometric security.

## Guidelines & Rules

All code and design contributions must follow:
1. [Swift Guidelines](file:///Users/lucas/Documents/Develop/cofrinho/.agents/rules/swift-guidelines.md)
2. [iOS Cofrinho Standards](file:///Users/lucas/Documents/Develop/cofrinho/.agents/rules/ios-cofrinho-standards.md)
3. Available Skills in `.agents/skills/`:
   - iOS: `swift-charts`, `swiftdata`, `financekit`, `widgetkit`, `swift-formatstyle`, `swift-concurrency`, `swiftui-patterns`, `swiftui-layout-components`, `swiftui-gestures`, `swiftui-animation`, `ios-localization`, `swift-security`.

## Xcode MCP Integration
The project uses Apple's official `xcrun mcpbridge`:
- `DocumentationSearch`: Consultar documentação oficial de APIs Apple antes de codificar.
- `BuildProject`: Validar compilação do projeto no Xcode.
- `GetBuildLog`: Obter diagnósticos estruturados de erros.
- `RenderPreview`: Renderizar e inspecionar previews SwiftUI.

## Key Commands & Workflow
- **Current Target**: Native iOS inside `ios/Cofrinho.xcodeproj` (source in `ios/CofrinhoApp/`).
- **UI Framework**: SwiftUI targeting iOS 17+ with Swift 6 strict concurrency.
- **Data & Charts**: SwiftData offline-first for transactions, budgets, and savings goals; Swift Charts for monthly evolution, category donut charts, and spending limits.
- **State Management**: `@Observable` classes marked `@MainActor`, injected with `@State`, `@Bindable`, or `@Environment`.
- **Formatting**: Always modern `FormatStyle` (e.g. `amount.formatted(.currency(code: "BRL"))`, `date.formatted(date: .abbreviated, time: .omitted)`).
- **Security**: Optional Face ID / Touch ID biometric lock via `LocalAuthentication`.

