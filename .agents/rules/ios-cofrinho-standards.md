# Cofrinho iOS Standards & Architecture

## 1. Visão Geral & Filosofia
- **100% Offline-First**: Dados do usuário pertencem ao usuário. Não há contas externas nem telemetria invasiva.
- **Simplicidade & Elegância**: Interface nativa SwiftUI fluida, rápida e responsiva.
- **Passo a Passo**: Construção modular, sustentável e testada.

## 2. Padrões de Código e Arquitetura
- **MVVM / MV Moderno**:
  - Views consom models e view models reativos usando `@Observable` e `@MainActor`.
  - Injeção via `@Environment` ou passagem direta de instâncias `@Bindable`.
- **Persistência**:
  - SwiftData como única fonte da verdade para transações, categorias, orçamentos e metas financeiras.
- **Formatação de Dados**:
  - Utilizar sempre `FormatStyle` nativo para moeda (`.currency(code: "BRL")`), números e datas.
- **Componentização**:
  - Subviews pequenas e dedicadas para manter previews rápidos e código legível.
- **Gerenciamento de Projeto**:
  - O projeto é gerenciado via **XcodeGen** (`ios/project.yml`).
  - Qualquer adição de arquivos estruturais ou configurações deve ser refletida de forma limpa no `project.yml`.

