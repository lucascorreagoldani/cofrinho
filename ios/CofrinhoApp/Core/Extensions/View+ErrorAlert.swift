import SwiftUI

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

