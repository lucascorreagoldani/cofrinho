# Swift & SwiftUI Senior Engineering Guidelines

Target: **iOS 17+ / iOS 18+**, **Swift 6+** with strict concurrency.

## 1. Concurrency & Architecture
- **Strict Concurrency**: Always use modern Swift Concurrency (`async`/`await`, `Task`, `actors`). Never use legacy Grand Central Dispatch (`DispatchQueue.main.async()`, `DispatchQueue.global()`).
- **State Management**:
  - Use `@Observable` classes marked with `@MainActor` for shared state and view models.
  - Own instances using `@State`, pass bindings using `@Bindable`, inject dependencies using `@Environment`.
  - **Never** use legacy `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`.
- **Error Handling**: Avoid force unwrapping (`!`) and force `try!` unless mathematically or architecturally impossible to fail. Handle errors gracefully with typed throws or user-facing alerts.

## 2. Modern SwiftUI Conventions
- **Styling**:
  - Always use `foregroundStyle()` instead of `foregroundColor()`.
  - Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
  - Use dynamic standard colors or assets that support Dark/Light modes seamlessly.
- **View Hierarchy**:
  - Decompose large views into small, focused sub-views (`struct MySubView: View`). Avoid large computed properties returning `some View`.
  - Use `NavigationStack` with `navigationDestination(for:)` for programmatic, type-safe navigation.
  - Use `containerRelativeFrame()` or `visualEffect()` instead of `GeometryReader` whenever possible.
  - Use `Tab` API instead of legacy `tabItem()`.
  - Use `.scrollIndicators(.hidden)` rather than initializer arguments.
- **Formatting & Strings**:
  - Never use `String(format: "%.2f", ...)`. Always use `FormatStyle`: e.g. `value.formatted(.number.precision(.fractionLength(2)))` or `date.formatted(date: .abbreviated, time: .shortened)`.
  - Use `localizedStandardContains()` for user search filtering.

## 3. SwiftData Persistence
- Models must be annotated with `@Model`.
- If CloudKit sync is configured:
  - Do not use `@Attribute(.unique)`.
  - Properties must have default values or be optional.
  - Relationships must be optional.

## 4. Testing
- Use the modern **Swift Testing** framework (`import Testing`, `@Test`, `#expect(...)`) instead of legacy XCTest when creating new tests.
