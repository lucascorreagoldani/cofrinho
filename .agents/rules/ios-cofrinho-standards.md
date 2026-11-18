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
- **Navegação Principal & Hub `Início` (5 Abas)**:
  - A barra inferior (`MainTabView`) segue exatamente a ordem: **`Início` (`house.fill`) | `Extrato` (`list.bullet.rectangle.portrait.fill`) | `Lançamento` (`plus.circle.fill`) | `Objetivos` (`target`) | `Perfil` (`person.crop.circle.fill`)**.
  - A aba **`Início`** (`HomeHubView`) reúne:
    - Botão de destaque **`Novo Lançamento`**, abrindo sheet modal com `NavigationStack` idêntico ao botão `+` do `Extrato`.
    - Card **`Meu dinheiro`** com saldo disponível (`Receitas - Gastos`), resumo de entradas/saídas e botão **`?`** no canto superior direito que, ao ser clicado, **some permanentemente naquela conta** (voltando apenas ao trocar de conta ou reinstalar o app) e abre um **overlay em tela cheia com fundo em blur** (`.ultraThinMaterial` + `.blur` sobre a `TabView`), tipografia editorial Apple HIG, hierarquia de SF Symbols animados e atalhos interativos diretos para **`RECEITA`** e **`GASTO`**.
    - Card de gráfico **`Gastos x Receita`** em **`Swift Charts`** (`BarMark`) exibindo os valores atuais consolidados (com alternância `Geral` / `Este Mês`).
- **Fluxo de Lançamentos (`Lançamento` / `Novo Lançamento`)**:
  - Permite alternar entre **`Gasto`** (`expense`) e **`Receita`** (`income`) via enum `TransactionType`.
  - Respeitar `defaultTransactionType` das preferências do usuário em **tempo real** (via `.onChange(of: defaultType)` e `applyDefaultType`, sem exigir reinício do app) e ocultar/desativar parcelamento quando o tipo for `.income`.
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

