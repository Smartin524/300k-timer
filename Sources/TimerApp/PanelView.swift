import SwiftUI
import TimerCore

struct PanelView: View {
    @ObservedObject var store: FocusStore
    let dismissPanel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("300k Timer").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if store.showsSettings || store.showsWasteTime {
                    headerButton("chevron.left", label: "返回计时") {
                        store.showsSettings = false
                        store.showsWasteTime = false
                    }
                } else {
                    HStack(spacing: 4) {
                        headerButton("fish", label: "摸鱼时间") { store.showsWasteTime = true }
                        headerButton("chart.bar.xaxis", label: "统计") { store.showsSettings = true }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 10)

            if store.showsSettings { settings.padding(.top, 12) }
            else if store.showsWasteTime {
                WasteTimeView(ledger: store.state.wasteTime ?? WasteTimeState(), activeSite: store.wasteSite)
            } else { timer }

            if let message = store.storageError ?? store.websiteWarning {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .frame(width: 260)

    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 24)
        }
        .buttonStyle(QuietHoverButtonStyle())
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }

    private var timer: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(TimeText.clock(store.state.sessionSeconds))
                    .font(.system(size: 36, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .accessibilityLabel("本次计时 \(TimeText.clock(store.state.sessionSeconds))")
                // An automatic pause explains itself in the status line, so no row is reserved for it.
                Text(store.pauseNotice ?? store.state.phase.title)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.top, 8)

            HStack(spacing: 12) {
                if store.pauseNotice != nil { keepPausedButton }
                primaryButton
            }
            Text("今日 \(TimeText.compact(store.today))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.bottom, 14)
    }

    private var primaryButton: some View {
        Button { store.toggle() } label: {
            Image(systemName: store.state.isRunning ? "pause.fill" : "play.fill")
                .renderingMode(.template)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(SolidIconButtonStyle(tint: store.state.isRunning ? .orange : .green))
        .accessibilityLabel(store.state.isRunning ? "暂停" : "开始或继续")
        .help(store.state.isRunning ? "暂停（⌥T）" : "开始或继续（⌥T）")
        .keyboardShortcut(.space, modifiers: [])
    }

    private var keepPausedButton: some View {
        Button {
            store.keepPaused()
            dismissPanel()
        } label: {
            Image(systemName: "pause.fill").font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(SolidIconButtonStyle(tint: .orange))
        .accessibilityLabel("保持暂停")
        .help("保持暂停并收起面板")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("历史总时长").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(TimeText.clock(store.totalSeconds))
                    .font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit()
            }
            let records = store.dailyRecords
            VStack(alignment: .leading, spacing: 8) {
                if records.isEmpty {
                    Text("暂无记录").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(records, id: \.day) { record in
                                HStack {
                                    Text(record.day).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(TimeText.clock(record.seconds)).monospacedDigit()
                                }.font(.system(size: 12))
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    // Hidden so the durations stay aligned with the total above; the cut-off row hints at more.
                    .scrollIndicators(.hidden)
                    .frame(height: min(84, CGFloat(records.count) * 26))
                }
            }
            HourlyActivityView(state: store.state)
            Divider()
            LoginItemToggle().font(.system(size: 11))
            HStack(spacing: 12) {
                Picker("闲置暂停", selection: Binding(get: { store.state.settings.idleMinutes }, set: { value in
                    store.updateSettings { $0.idleMinutes = value }
                })) {
                    Text("关闭").tag(0)
                    Text("5 分钟").tag(5)
                    Text("10 分钟").tag(10)
                    Text("15 分钟").tag(15)
                }.fixedSize()
                Spacer(minLength: 0)
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(QuietHoverButtonStyle(horizontalPadding: 7))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16).padding(.bottom, 14)
    }
}

/// Fixed sRGB fills keep colored actions consistent across light and dark glass.
private struct SolidIconButtonStyle: ButtonStyle {
    enum Tint {
        case orange, green

        var color: Color {
            switch self {
            case .orange: return Color(.sRGB, red: 0.95, green: 0.49, blue: 0.08, opacity: 1)
            case .green: return Color(.sRGB, red: 0.16, green: 0.73, blue: 0.32, opacity: 1)
            }
        }
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let tint: Tint?
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
            .background {
                Circle().fill(tint?.color ?? Color.primary.opacity(0.10))
                    .overlay {
                        // Apply feedback to the fill only, keeping the glyph crisp.
                        Circle().fill(tint == nil ? Color.primary : Color.black)
                            .opacity(!isEnabled ? 0 : configuration.isPressed ? 0.20 :
                                isHovered ? (colorScheme == .dark ? 0.12 : 0.08) : 0)
                    }
            }
            // Flatten only the button, not the native glass backdrop.
            .drawingGroup()
            .opacity(isEnabled ? 1 : 0.3)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .onDisappear { isHovered = false }
    }
}
