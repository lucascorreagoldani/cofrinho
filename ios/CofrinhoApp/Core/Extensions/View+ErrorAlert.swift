import SwiftUI
import UIKit

// MARK: - 1. Framework de Tratamento Global de Erros (CofrinhoErrorMapper + Alert Modifiers)

/// Utilitário centralizado para normalizar qualquer `Error` no protocolo `AppErrorProtocol`
/// e classificar falhas transitórias de conectividade (modo offline resiliente).
public enum CofrinhoErrorMapper {
    public static func normalize(_ error: any Error) -> any AppErrorProtocol {
        if let appErr = error as? any AppErrorProtocol {
            return appErr
        }
        return NetworkError.unknown(reason: error.localizedDescription)
    }

    public static func isConnectivityIssue(_ error: any AppErrorProtocol) -> Bool {
        guard let netErr = error as? NetworkError else { return false }
        switch netErr {
        case .noConnection, .serverUnreachable, .timeout:
            return true
        default:
            return false
        }
    }

    public static func isConnectivityIssue(_ error: any Error) -> Bool {
        isConnectivityIssue(normalize(error))
    }
}

public extension View {
    /// Apresenta um alerta nativo padronizado do SwiftUI para erros específicos tipados.
    func handleAppError<E: AppErrorProtocol>(
        _ error: Binding<E?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        alert(
            error.wrappedValue?.errorDescription ?? "Ocorreu um erro",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        error.wrappedValue = nil
                        onDismiss?()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                error.wrappedValue = nil
                onDismiss?()
            }
        } message: {
            if let suggestion = error.wrappedValue?.recoverySuggestion {
                Text(suggestion)
            }
        }
    }

    /// Apresenta um alerta nativo padronizado para qualquer erro genérico que implemente `AppErrorProtocol`.
    func handleAnyAppError(
        _ error: Binding<(any AppErrorProtocol)?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        alert(
            error.wrappedValue?.errorDescription ?? "Ocorreu um erro",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        error.wrappedValue = nil
                        onDismiss?()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                error.wrappedValue = nil
                onDismiss?()
            }
        } message: {
            if let suggestion = error.wrappedValue?.recoverySuggestion {
                Text(suggestion)
            }
        }
    }
}

// MARK: - 2. Framework POO de Botões Reutilizáveis (CofrinhoButton & CofrinhoChipButton)

/// Papéis semânticos globais para botões no Cofrinho, preservando as regras canônicas de cor:
/// Editar = Laranja, Excluir = Vermelho, Receita = Verde, Gasto/Primário = Índigo/Azul.
public enum CofrinhoButtonSemanticRole: Sendable, Equatable {
    case primary
    case heroGradient
    case income
    case expense
    case edit
    case editTinted
    case destructive
    case destructiveTinted
    case neutral
    case editorialCapsule
}

/// Tamanhos ergonômicos padronizados (Apple HIG >= 44pt em ações principais).
public enum CofrinhoButtonSize: Sendable, Equatable {
    case compact
    case regular
    case large
    case hero
}

/// Botão orientado a objetos reutilizável com suporte a subtítulo, ícone, loading spinner e feedback háptico.
public struct CofrinhoButton: View {
    public let title: String
    public let subtitle: String?
    public let systemImage: String?
    public let trailingSystemImage: String?
    public let role: CofrinhoButtonSemanticRole
    public let size: CofrinhoButtonSize
    public let isLoading: Bool
    public let isFullWidth: Bool
    public let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle
    public let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        trailingSystemImage: String? = nil,
        role: CofrinhoButtonSemanticRole = .primary,
        size: CofrinhoButtonSize = .regular,
        isLoading: Bool = false,
        isFullWidth: Bool = true,
        hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self.role = role
        self.size = size
        self.isLoading = isLoading
        self.isFullWidth = isFullWidth
        self.hapticStyle = hapticStyle
        self.action = action
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .compact: return 10
        case .regular: return 12
        case .large: return 14
        case .hero: return 18
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: return 8
        case .regular: return 12
        case .large: return 14
        case .hero: return 16
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: return 12
        case .regular: return 16
        case .large: return 22
        case .hero: return 18
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary, .heroGradient, .income, .expense, .edit, .destructive:
            return .white
        case .editTinted:
            return .orange
        case .destructiveTinted:
            return .red
        case .neutral:
            return .primary
        case .editorialCapsule:
            return Color(.systemBackground)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch role {
        case .heroGradient:
            LinearGradient(
                colors: [
                    Color.blue,
                    Color(red: 0.25, green: 0.35, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .primary:
            Color.blue
        case .income:
            Color.green
        case .expense:
            Color(red: 0.31, green: 0.27, blue: 0.90)
        case .edit:
            Color.orange
        case .editTinted:
            Color.orange.opacity(0.14)
        case .destructive:
            Color.red
        case .destructiveTinted:
            Color.red.opacity(0.14)
        case .neutral:
            Color(.secondarySystemBackground)
        case .editorialCapsule:
            Color.primary
        }
    }

    private var shadowColor: Color {
        switch role {
        case .heroGradient: return Color.blue.opacity(0.28)
        case .primary: return Color.blue.opacity(0.24)
        case .income: return Color.green.opacity(0.28)
        case .expense: return Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.32)
        case .edit: return Color.orange.opacity(0.25)
        case .destructive: return Color.red.opacity(0.25)
        case .editTinted, .destructiveTinted, .neutral, .editorialCapsule: return .clear
        }
    }

    public var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: hapticStyle)
            haptic.impactOccurred()
            action()
        } label: {
            Group {
                if size == .hero {
                    heroContent
                } else {
                    standardContent
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(backgroundView)
            .foregroundStyle(foregroundColor)
            .clipShape(
                role == .editorialCapsule
                ? AnyShape(Capsule())
                : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .shadow(color: shadowColor, radius: size == .hero ? 10 : 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var standardContent: some View {
        HStack(spacing: 8) {
            if isFullWidth { Spacer(minLength: 0) }
            if isLoading {
                ProgressView()
                    .tint(foregroundColor)
            } else {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                }
                Text(title)
                    .font(size == .compact ? .subheadline.weight(.semibold) : .headline.weight(.bold))
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.subheadline.bold())
                }
            }
            if isFullWidth { Spacer(minLength: 0) }
        }
    }

    private var heroContent: some View {
        HStack(spacing: 14) {
            if let systemImage {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(foregroundColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(foregroundColor.opacity(0.86))
                }
            }

            Spacer()

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(foregroundColor.opacity(0.9))
            }
        }
    }
}

/// Chip selecionável reutilizável para barras de navegação e filtros temporais.
public struct CofrinhoChipButton: View {
    public let title: String
    public let isSelected: Bool
    public let isMonospacedDigits: Bool
    public let accentColor: Color
    public let action: () -> Void

    public init(
        title: String,
        isSelected: Bool,
        isMonospacedDigits: Bool = false,
        accentColor: Color = .blue,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isMonospacedDigits = isMonospacedDigits
        self.accentColor = accentColor
        self.action = action
    }

    public var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        } label: {
            Text(title)
                .font(isMonospacedDigits ? .caption.bold().monospacedDigit() : .caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? accentColor : Color(.systemBackground))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. Framework POO de Avisos de Ajuda (?) Permanentes & Spotlight Apple HIG

/// Identificadores canônicos de ações disparadas a partir de links ou atalhos nos avisos de ajuda.
public enum HelpActionTag: Sendable {
    public static let launchIncome = "launch_income"
    public static let launchExpense = "launch_expense"
    public static let goToStatement = "go_to_statement"
}

/// Segmento tipado para compor textos de ajuda com hiperlinks interativos sem boilerplate.
public enum HelpTextSegment: Hashable, Sendable {
    case plain(String)
    case link(label: String, actionTag: String, color: Color)
}

/// Ação rápida listada em estilo agrupado Apple HIG dentro do spotlight de ajuda.
public struct HelpQuickAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let tintColor: Color
    public let actionTag: String

    public init(
        id: String? = nil,
        title: String,
        subtitle: String,
        systemImage: String,
        tintColor: Color,
        actionTag: String
    ) {
        self.id = id ?? "\(actionTag)_\(title)"
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tintColor = tintColor
        self.actionTag = actionTag
    }
}

/// Contrato POO para qualquer aviso/tutorial contextual acionado por botões "?".
public protocol HelpNoticeProtocol: Identifiable, Sendable {
    var id: String { get }
    var badgeTitle: String { get }
    var headline: String { get }
    var systemImage: String { get }
    var accentColor: Color { get }
    var segments: [HelpTextSegment] { get }
    var quickActions: [HelpQuickAction] { get }
    var dismissButtonTitle: String { get }
}

/// Modelo concreto reutilizável de aviso de ajuda no padrão Cofrinho.
public struct HelpNoticeItem: HelpNoticeProtocol, Equatable, Sendable {
    public let id: String
    public let badgeTitle: String
    public let headline: String
    public let systemImage: String
    public let accentColor: Color
    public let segments: [HelpTextSegment]
    public let quickActions: [HelpQuickAction]
    public let dismissButtonTitle: String

    public init(
        id: String,
        badgeTitle: String,
        headline: String,
        systemImage: String,
        accentColor: Color = .blue,
        segments: [HelpTextSegment],
        quickActions: [HelpQuickAction] = [],
        dismissButtonTitle: String = "Entendi"
    ) {
        self.id = id
        self.badgeTitle = badgeTitle
        self.headline = headline
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.segments = segments
        self.quickActions = quickActions
        self.dismissButtonTitle = dismissButtonTitle
    }

    /// Constrói `AttributedString` com links internos roteados pelo `HelpSpotlightOverlayView`.
    public func renderedAttributedText() -> AttributedString {
        var combined = AttributedString()
        for segment in segments {
            switch segment {
            case .plain(let text):
                combined.append(AttributedString(text))
            case .link(let label, let actionTag, let color):
                var part = AttributedString(label)
                part.link = URL(string: "cofrinho-help://action/\(actionTag)")
                part.foregroundColor = color
                part.underlineStyle = .single
                part.font = .body.weight(.semibold)
                combined.append(part)
            }
        }
        return combined
    }
}

/// Catálogo centralizado de avisos de ajuda reutilizáveis nas telas do Cofrinho.
public enum HelpNoticeCatalog {
    public static let myMoney = HelpNoticeItem(
        id: "home_my_money",
        badgeTitle: "Meu dinheiro",
        headline: "Acompanhe seu saldo em tempo real",
        systemImage: "wallet.pass.fill",
        accentColor: .blue,
        segments: [
            .plain("Aqui fica o seu saldo disponível, adicione um lançamento de "),
            .link(label: "RECEITA", actionTag: HelpActionTag.launchIncome, color: .green),
            .plain(" e lançamentos de "),
            .link(label: "GASTO", actionTag: HelpActionTag.launchExpense, color: .red),
            .plain(" para visualizar a movimentação do seu dinheiro.")
        ],
        quickActions: [
            HelpQuickAction(
                title: "Lançar uma Receita",
                subtitle: "Salário, Pix recebido ou entrada extra",
                systemImage: "arrow.down.left.circle.fill",
                tintColor: .green,
                actionTag: HelpActionTag.launchIncome
            ),
            HelpQuickAction(
                title: "Lançar um Gasto",
                subtitle: "Compras do dia, cartão ou contas",
                systemImage: "arrow.up.right.circle.fill",
                tintColor: .red,
                actionTag: HelpActionTag.launchExpense
            )
        ]
    )

    public static let cashflowChart = HelpNoticeItem(
        id: "home_cashflow_chart",
        badgeTitle: "Gastos x Receita",
        headline: "Compare entradas e saídas",
        systemImage: "chart.bar.xaxis",
        accentColor: .blue,
        segments: [
            .plain("Este gráfico compara o total de "),
            .link(label: "RECEITA", actionTag: HelpActionTag.launchIncome, color: .green),
            .plain(" contra os seus lançamentos de "),
            .link(label: "GASTO", actionTag: HelpActionTag.launchExpense, color: .red),
            .plain(". Use o seletor acima das barras para alternar entre o acumulado geral e o mês atual.")
        ],
        quickActions: [
            HelpQuickAction(
                title: "Adicionar Receita",
                subtitle: "Somar nova entrada no comparativo",
                systemImage: "arrow.down.left.circle.fill",
                tintColor: .green,
                actionTag: HelpActionTag.launchIncome
            ),
            HelpQuickAction(
                title: "Adicionar Gasto",
                subtitle: "Registrar uma nova despesa",
                systemImage: "arrow.up.right.circle.fill",
                tintColor: .red,
                actionTag: HelpActionTag.launchExpense
            )
        ]
    )

    public static let statementOverview = HelpNoticeItem(
        id: "transactions_statement_help",
        badgeTitle: "Extrato Inteligente",
        headline: "Navegue pelos seus dias e edite com gestos",
        systemImage: "list.bullet.rectangle.portrait.fill",
        accentColor: .blue,
        segments: [
            .plain("Deslize o card de resumo ou use os botões da barra superior para alternar entre dias com lançamentos. Em qualquer linha, deslize para a direita para editar (laranja) ou para a esquerda para excluir (vermelho) e ocultar.")
        ],
        quickActions: [
            HelpQuickAction(
                title: "Nova Receita",
                subtitle: "Registrar entrada diretamente no extrato",
                systemImage: "arrow.down.left.circle.fill",
                tintColor: .green,
                actionTag: HelpActionTag.launchIncome
            ),
            HelpQuickAction(
                title: "Novo Gasto",
                subtitle: "Registrar despesa à vista ou parcelada",
                systemImage: "arrow.up.right.circle.fill",
                tintColor: .red,
                actionTag: HelpActionTag.launchExpense
            )
        ]
    )

    public static let goalsPreview = HelpNoticeItem(
        id: "goals_overview_help",
        badgeTitle: "Cofrinhos & Objetivos",
        headline: "Planejamento de economia inteligente",
        systemImage: "target",
        accentColor: .green,
        segments: [
            .plain("Enquanto preparamos seus cofrinhos dedicados de metas, registre suas "),
            .link(label: "RECEITAS", actionTag: HelpActionTag.launchIncome, color: .green),
            .plain(" e controle seus "),
            .link(label: "GASTOS", actionTag: HelpActionTag.launchExpense, color: .red),
            .plain(" para construir reserva mensal.")
        ],
        quickActions: [
            HelpQuickAction(
                title: "Registrar Receita",
                subtitle: "Aporte de entrada no seu saldo",
                systemImage: "arrow.down.left.circle.fill",
                tintColor: .green,
                actionTag: HelpActionTag.launchIncome
            )
        ]
    )
}

/// Botão "?" permanente e reutilizável para acionar qualquer `HelpNoticeItem`.
public struct HelpNoticeTriggerButton: View {
    public let notice: HelpNoticeItem
    public let onTrigger: (HelpNoticeItem) -> Void

    public init(
        notice: HelpNoticeItem,
        onTrigger: @escaping (HelpNoticeItem) -> Void
    ) {
        self.notice = notice
        self.onTrigger = onTrigger
    }

    public var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            onTrigger(notice)
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 21, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(notice.accentColor)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajuda sobre \(notice.badgeTitle)")
    }
}

/// Overlay full-screen Apple HIG com `.ultraThinMaterial`, SF Symbols animados e ações contextuais.
public struct HelpSpotlightOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var symbolBounceTrigger: Bool = false

    public let notice: HelpNoticeItem
    public let onSelectActionTag: (String) -> Void
    public let onDismiss: () -> Void

    public init(
        notice: HelpNoticeItem,
        onSelectActionTag: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.notice = notice
        self.onSelectActionTag = onSelectActionTag
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay {
                    Color.black
                        .opacity(colorScheme == .dark ? 0.36 : 0.14)
                        .ignoresSafeArea()
                }
                .onTapGesture {
                    let haptic = UISelectionFeedbackGenerator()
                    haptic.selectionChanged()
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(notice.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .frame(width: 52, height: 52)

                        Image(systemName: notice.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(notice.accentColor)
                            .symbolEffect(.bounce.up.byLayer, value: symbolBounceTrigger)
                    }

                    Spacer()

                    Button {
                        let haptic = UISelectionFeedbackGenerator()
                        haptic.selectionChanged()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar ajuda")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(notice.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(notice.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(notice.headline)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(notice.renderedAttributedText())
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(.primary)
                        .environment(\.openURL, OpenURLAction { url in
                            let prefix = "cofrinho-help://action/"
                            if url.absoluteString.hasPrefix(prefix) {
                                let actionTag = String(url.absoluteString.dropFirst(prefix.count))
                                onSelectActionTag(actionTag)
                                return .handled
                            }
                            return .systemAction
                        })
                }

                if !notice.quickActions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(notice.quickActions.enumerated()), id: \.element.id) { index, quickAction in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 58)
                            }
                            spotlightActionRow(quickAction)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground).opacity(colorScheme == .dark ? 0.72 : 0.85))
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }

                CofrinhoButton(
                    title: notice.dismissButtonTitle,
                    role: .editorialCapsule,
                    size: .large,
                    hapticStyle: .light
                ) {
                    onDismiss()
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 32, y: 14)
            .padding(.horizontal, 20)
        }
        .onAppear {
            symbolBounceTrigger.toggle()
        }
    }

    private func spotlightActionRow(_ quickAction: HelpQuickAction) -> some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            onSelectActionTag(quickAction.actionTag)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: quickAction.systemImage)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(quickAction.tintColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(quickAction.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(quickAction.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

public extension View {
    /// Aplica blur óptico e profundidade na view raiz e apresenta qualquer `HelpNoticeItem` em tela cheia.
    func cofrinhoHelpOverlay(
        activeNotice: Binding<HelpNoticeItem?>,
        reduceMotion: Bool = false,
        onAction: @escaping (String) -> Void
    ) -> some View {
        let isShowing = activeNotice.wrappedValue != nil
        let motion: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(duration: 0.42, bounce: 0.16)

        return self
            .blur(radius: isShowing ? 14 : 0)
            .scaleEffect(isShowing ? 0.97 : 1.0)
            .allowsHitTesting(!isShowing)
            .animation(motion, value: activeNotice.wrappedValue?.id)
            .overlay {
                if let notice = activeNotice.wrappedValue {
                    HelpSpotlightOverlayView(
                        notice: notice,
                        onSelectActionTag: { actionTag in
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.12)) {
                                activeNotice.wrappedValue = nil
                            }
                            onAction(actionTag)
                        },
                        onDismiss: {
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.12)) {
                                activeNotice.wrappedValue = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(100)
                }
            }
            .animation(motion, value: activeNotice.wrappedValue?.id)
    }
}

