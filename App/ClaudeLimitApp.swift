import SwiftUI
import WidgetKit

@main
struct ClaudeLimitApp: App {
    @StateObject private var model = UsageViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            if let image = model.menuBarImage {
                Image(nsImage: image)
            } else {
                Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var planName: String?
    @Published var menuBarImage: NSImage?
    
    /// >= 180s per the endpoint's rate limit.
    private let refreshInterval: TimeInterval = 180
    private var timer: Timer?
    
    init() {
        snapshot = UsageStore.load()
        updateMenuBarImage()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }
    
    var menuBarTitle: String {
        guard let u = snapshot?.fiveHour?.utilization else { return "--" }
        return "\(Int(u))%"
    }
    
    var menuBarSymbol: String {
        guard let u = snapshot?.fiveHour?.utilization else { return "gauge" }
        switch u {
        case ..<50: return "gauge.with.dots.needle.33percent"
        case ..<80: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }
    
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        planName = CredentialsProvider.subscriptionType()?.capitalized
        do {
            let fresh = try await UsageAPI.fetch()
            snapshot = fresh
            errorMessage = nil
            UsageStore.save(fresh)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
        updateMenuBarImage()
    }

    /// MenuBarExtra flattens SwiftUI labels to a template image (colors are lost),
    /// so the status is pre-rendered into a non-template NSImage instead.
    private func updateMenuBarImage() {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = MenuBarStatusView(
            session: snapshot?.fiveHour?.utilization,
            weekly: snapshot?.sevenDay?.utilization,
            models: (snapshot?.weeklyModelWindows ?? []).compactMap { item in
                item.window.utilization.map { (item.name, $0) }
            },
            isDark: isDark
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = false
        menuBarImage = image
    }
}

/// Compact status drawn into the menu bar: session + weekly (+ per-model),
/// each with a mini bar.
private struct MenuBarStatusView: View {
    let session: Double?
    let weekly: Double?
    let models: [(String, Double)]
    let isDark: Bool

    private var labelColor: Color { isDark ? Color(white: 0.8) : Color(white: 0.3) }

    var body: some View {
        HStack(spacing: 8) {
            segment(label: "5h", value: session)
            segment(label: "7d", value: weekly)
            ForEach(models, id: \.0) { model in
                segment(label: "7d", value: model.1)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 16)
        .fixedSize()
    }

    private func segment(label: String, value: Double?) -> some View {
        let u = value ?? 0
        return HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(labelColor)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(value != nil ? "\(Int(u))%" : "--")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(value != nil ? color(for: u) : labelColor)
                    .fixedSize()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: isDark ? 0.7 : 0.4).opacity(0.35))
                        .frame(width: 30, height: 4)
                    Capsule()
                        .fill(color(for: u))
                        .frame(width: max(3, 30 * min(u, 100) / 100), height: 4)
                }
            }
        }
    }

    private func color(for utilization: Double) -> Color {
        switch utilization {
        case ..<50: return .green
        case ..<80: return .orange
        default: return .red
        }
    }
}
