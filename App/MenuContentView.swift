import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = model.snapshot {
                sessionCard(snapshot)
                weeklyCard(snapshot)
            } else {
                emptyState
            }

            if let error = model.errorMessage {
                errorBanner(error)
            }

            if model.tokenExpired {
                refreshTokenButton
            }

            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Plan usage limits")
                .font(.system(.headline, design: .rounded))
            if let plan = model.planName {
                Text(plan)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
        }
    }

    // MARK: - Cards

    private func sessionCard(_ snapshot: UsageSnapshot) -> some View {
        card {
            sectionLabel("Current session", systemImage: "clock")

            let u = snapshot.fiveHour?.utilization ?? 0
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(u))")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(usageColor(u))
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let resets = snapshot.fiveHour?.resetsAt,
                   let text = resetText(for: resets) {
                    Label(text, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            UsageBar(value: u)
        }
    }

    private func weeklyCard(_ snapshot: UsageSnapshot) -> some View {
        card {
            sectionLabel("Weekly limits", systemImage: "calendar")

            LimitRow(title: "All models", window: snapshot.sevenDay)

            ForEach(snapshot.weeklyModelWindows, id: \.name) { item in
                Divider()
                LimitRow(title: item.name, window: item.window)
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        card {
            HStack(spacing: 10) {
                Image(systemName: "gauge")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No data yet")
                        .font(.subheadline)
                    Text("Press refresh to fetch the latest usage")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var refreshTokenButton: some View {
        Button {
            Task { await model.refreshToken() }
        } label: {
            HStack(spacing: 6) {
                if model.isRefreshingToken {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "key.horizontal.fill")
                }
                Text(model.isRefreshingToken ? "Refreshing…" : "Refresh token")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
        .disabled(model.isRefreshingToken)
        .help("Exchange the stored refresh token for a new access token")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let snapshot = model.snapshot {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if snapshot.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .help("Data may be out of date")
                }
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.5)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Row

private struct LimitRow: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        let u = window?.utilization ?? 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                Spacer()
                Text("\(Int(u))%")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(usageColor(u))
            }
            UsageBar(value: u)
            if let resets = window?.resetsAt, let text = resetText(for: resets) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Bar

private struct UsageBar: View {
    let value: Double // 0–100

    var body: some View {
        GeometryReader { geo in
            let fraction = min(max(value, 0), 100) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(
                        colors: [usageColor(value).opacity(0.65), usageColor(value)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

// MARK: - Helpers

private func usageColor(_ utilization: Double) -> Color {
    switch utilization {
    case ..<50: return .green
    case ..<80: return .orange
    default: return .red
    }
}

private func resetText(for date: Date) -> String? {
    let remaining = date.timeIntervalSinceNow
    guard remaining > 0 else { return "Reset" }
    let formatter = DateComponentsFormatter()
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: "en_US")
    formatter.calendar = calendar
    formatter.allowedUnits = remaining >= 86400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    guard let text = formatter.string(from: remaining) else { return nil }
    return "Resets in \(text)"
}
