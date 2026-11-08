import SwiftUI
import SwiftData

@main
struct CofrinhoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(LocalDataManager.shared.container)
    }
}
