# Cofrinho iOS Standards & Architecture

## 1. Visão Geral & Filosofia
- **Offline-First com Sync Seguro**: Dados do usuário pertencem ao usuário, com persistência local em SwiftData e sincronização autenticada opcional/contínua com a API Privada (PostgreSQL + Redis).
- **Simplicidade & Elegância**: Interface nativa SwiftUI fluida, rápida e responsiva.
- **Passo a Passo**: Construção modular, sustentável e testada.

## 2. Padrões de Código e Arquitetura
- **MVVM / MV Moderno**:
  - Views consomem models e view models reativos usando `@Observable` e `@MainActor`.
  - Injeção via `@Environment` ou passagem direta de instâncias `@Bindable`.
- **Persistência**:
  - SwiftData (`LocalTransaction`, `LocalCategory`, `LocalAccount`) como base local reativa sincronizada com o backend PostgreSQL.
- **Formatação de Dados**:
  - Utilizar sempre `FormatStyle` nativo para moeda (`.currency(code: "BRL")`), números e datas (incluindo exibição condicional de horário quando presente).
- **Fluxo de Lançamentos (`Novo Lançamento`)**:
  - A aba e tela inicial padrão é **`Novo Lançamento`**, permitindo alternar entre **`Gasto`** (`expense`) e **`Receita`** (`income`) via enum `TransactionType`.
  - Respeitar `defaultTransactionType` das preferências do usuário ao inicializar ou resetar o formulário, e ocultar/desativar parcelamento quando o tipo for `.income`.
  - Oferecer toggle opcional **`Incluir horário específico`** (`hasTime`): preserva hora/minuto escolhidos quando ativo e normaliza para `12:00:00` local quando inativo (compatível com detecção visual no extrato).
- **Auditoria & Privacidade Visual**:
  - Exibir rastreabilidade completa de autoria no detalhe do lançamento: **`Adicionado por: @username`** (+ data/hora de criação) e, quando modificado, **`Modificado por: @username`** (+ data/hora da modificação).
  - Exibir exclusivamente o `@username` — **nunca exibir o e-mail** do criador ou modificador na interface.
- **Padrão Semântico Global de Cores**:
  - Ações de **Editar** devem utilizar sempre **Laranja (`Color.orange`)**.
  - Ações de **Excluir / Apagar** devem utilizar sempre **Vermelho (`Color.red`)**.
  - Esse padrão aplica-se uniformemente em *swipe actions* (`Extrato`), botões de detalhe, menus e CRUDs no `Perfil`.
- **Autonomia do Usuário & Contratos via Enum**:
  - O usuário possui autonomia via API Privada (`/v1/categories`, `/v1/accounts`, `/v1/users/me/preferences`) para criar, editar e excluir suas categorias, contas e padrões de lançamento, escolhendo ícones e cores padronizados pela API Pública (`/v1/public/enums`).
- **Componentização**:
  - Subviews pequenas e dedicadas para manter previews rápidos e código legível.
- **Gerenciamento de Projeto**:
  - O projeto é gerenciado via **XcodeGen** (`ios/project.yml`).
  - Qualquer adição de arquivos estruturais ou configurações deve ser refletida de forma limpa no `project.yml`.

