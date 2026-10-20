import SwiftUI
import TimerCore

extension Color {
    /// Shared by this page and the hourly chart, distinct from the green "running" state.
    static let wasteTime = Color(nsColor: .systemPink)
    static let studyTime = Color(nsColor: .systemBlue)
}

struct WasteTimeView: View {
    let ledger: WasteTimeState
    let activeSite: WasteSite?
    let studySeconds: TimeInterval

    private var day: String { StudyDay.key(for: Date()) }
    private var today: TimeInterval { ledger.seconds(on: day) }
    private var sites: [(site: WasteSite, seconds: TimeInterval)] {
        WasteSite.allCases.map { ($0, ledger.seconds(on: day, site: $0)) }
            .filter { $0.seconds > 0 }
            .sorted { $0.seconds > $1.seconds }
    }
    /// Oldest first, ending with today.
    private var week: [(day: String, label: String, seconds: TimeInterval)] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return (0..<7).reversed().map { offset in
            let start = StudyDay.start(for: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!)
            let key = FocusState.dayKey(start)
            let label = offset == 0 ? "今" : symbols[Calendar.current.component(.weekday, from: start) - 1]
            return (key, label, ledger.seconds(on: key))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            comparison
            breakdown
            Divider()
            weekChart
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日垃圾时间").font(.system(size: 11)).foregroundStyle(.secondary)
                DurationText(seconds: today, size: 30)
            }
            Spacer()
            if let activeSite {
                HStack(spacing: 4) {
                    Circle().fill(Color.wasteTime).frame(width: 5, height: 5)
                    Text(activeSite.title)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.wasteTime)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.wasteTime.opacity(0.14)))
                .accessibilityLabel("正在统计\(activeSite.title)")
            }
        }
    }

    /// Study vs. waste for today as one proportional bar.
    private var comparison: some View {
        let total = studySeconds + today
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                HStack(spacing: total > 0 && studySeconds > 0 && today > 0 ? 2 : 0) {
                    if total == 0 {
                        Capsule().fill(Color.primary.opacity(0.08))
                    } else {
                        if studySeconds > 0 {
                            Capsule().fill(Color.studyTime).frame(width: max(3, proxy.size.width * studySeconds / total))
                        }
                        if today > 0 { Capsule().fill(Color.wasteTime) }
                    }
                }
            }.frame(height: 5)
            HStack {
                label("学习", TimeText.compact(studySeconds), color: .studyTime)
                Spacer()
                if total > 0 {
                    Text("垃圾占 \(Int((today / total * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                label("垃圾", TimeText.compact(today), color: .wasteTime)
            }.font(.system(size: 10)).monospacedDigit()
        }
    }

    private var breakdown: some View {
        VStack(spacing: 9) {
            if sites.isEmpty {
                Text("今天还没有垃圾时间")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                ForEach(sites, id: \.site) { entry in
                    VStack(spacing: 4) {
                        HStack {
                            Text(entry.site.title)
                            Spacer()
                            Text(TimeText.clock(entry.seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.system(size: 12))
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule().fill(Color.wasteTime.opacity(entry.site == activeSite ? 1 : 0.7))
                                    .frame(width: max(4, proxy.size.width * entry.seconds / today))
                            }
                        }.frame(height: 4)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.site.title) \(TimeText.compact(entry.seconds))")
                }
            }
        }
    }

    private var weekChart: some View {
        let days = week
        let peak = max(days.map(\.seconds).max() ?? 0, 60)
        let average = days.map(\.seconds).reduce(0, +) / 7
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("近 7 天").foregroundStyle(.secondary)
                Spacer()
                Text("日均 \(TimeText.compact(average)) · 累计 \(TimeText.compact(ledger.total))")
                    .foregroundStyle(.tertiary)
            }.font(.system(size: 10)).monospacedDigit()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.day) { entry in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.seconds > 0 ? Color.wasteTime.opacity(entry.label == "今" ? 1 : 0.55)
                                                    : Color.primary.opacity(0.08))
                            .frame(height: entry.seconds > 0 ? max(3, 36 * entry.seconds / peak) : 2)
                            .frame(maxHeight: 36, alignment: .bottom)
                        Text(entry.label)
                            .font(.system(size: 9, weight: entry.label == "今" ? .semibold : .regular))
                            .foregroundStyle(entry.label == "今" ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .help("\(entry.day) · \(TimeText.clock(entry.seconds))")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.day) 垃圾时间 \(TimeText.compact(entry.seconds))")
                }
            }
        }
    }

    private func label(_ title: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

/// Large numerals with small units, e.g. 1h 23m or 42s.
private struct DurationText: View {
    let seconds: TimeInterval
    let size: CGFloat

    var body: some View {
        let value = max(0, Int(seconds))
        let parts: [(Int, String)] = value < 60 ? [(value, "s")]
            : value < 3600 ? [(value / 60, "m")]
            : [(value / 3600, "h"), (value / 60 % 60, "m")]
        return parts.reduce(Text("")) { text, part in
            text + Text("\(part.0)").font(.system(size: size, weight: .semibold))
                + Text(part.1 + " ").font(.system(size: size * 0.45, weight: .medium)).foregroundColor(.secondary)
        }
        .monospacedDigit()
    }
}
