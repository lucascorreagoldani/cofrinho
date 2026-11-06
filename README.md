# 🐷 Cofrinho - Gestão Financeira Pessoal & Economia Inteligente

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

---

## 🛠️ Stack Tecnológica

- **Linguagem**: Swift 6 (Strict Concurrency ativo).
- **Interface**: SwiftUI moderno (iOS 17+).
- **Persistência**: SwiftData offline-first.
- **Gráficos**: Apple Swift Charts (`SectorMark`, `BarMark`, `AreaMark`, `RuleMark`).
- **Segurança**: LocalAuthentication (`LAContext`).
- **Gerenciador de Projeto**: XcodeGen (`project.yml`).

---

## 🚀 Como Executar o Projeto

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

