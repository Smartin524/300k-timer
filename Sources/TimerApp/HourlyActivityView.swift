import SwiftUI
import TimerCore

/// Each bar is one local clock hour. Older daily totals remain unallocated.
struct HourlyActivityView: View {
    let state: TimerCore.FocusState
    @State private var selectedDate = Date()
    private var day: String { StudyDay.key(for: selectedDate) }
    private var hours: [String: TimeInterval] { state.studyHours(at: selectedDate) }
    private var wasteHours: [String: TimeInterval] { state.wasteTime?.hours(on: day) ?? [:] }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                    .accessibilityLabel("前一天")
                Spacer()
                Text(day == StudyDay.key(for: Date()) ? "今日时段" : day)
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                Spacer()
                Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                    .disabled(StudyDay.start(for: selectedDate) >= StudyDay.start(for: Date()))
                    .accessibilityLabel("后一天")
            }.buttonStyle(QuietButtonStyle()).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                legend("学习", color: .studyTime)
                legend("摸鱼时间", color: .wasteTime)
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            VStack(spacing: 3) {
                HStack {
                    Text("分钟")
                    Spacer()
                    Text("60")
                }.font(.system(size: 9)).foregroundStyle(.tertiary)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(StudyDay.boundaryHour...23) + Array(0..<StudyDay.boundaryHour), id: \.self) { hour in
                        let study = hours[String(hour), default: 0]
                        let waste = wasteHours[String(hour), default: 0]
                        HStack(alignment: .bottom, spacing: 1) {
                            bar(seconds: study, color: .studyTime)
                            bar(seconds: waste, color: .wasteTime)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .help(String(format: "%02d:00–%02d:00 · 学习 %@ · 摸鱼时间 %@", hour, hour + 1, TimeText.clock(study), TimeText.clock(waste)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(hour)点至\(hour + 1)点，学习\(Int(study / 60))分钟，摸鱼时间\(Int(waste / 60))分钟")
                    }
                }.frame(height: 64)
                    .background(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5) }
                HStack {
                    ForEach(["05", "12", "18", "00", "次日05"], id: \.self) { label in
                        Text(label)
                        if label != "次日05" { Spacer() }
                    }
                }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .onChange(of: StudyDay.key(for: Date())) { previous, _ in
            if day == previous { selectedDate = Date() }
        }
    }

    private func bar(seconds: TimeInterval, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: seconds > 0 ? max(2, 64 * min(seconds, 3600) / 3600) : 0)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(title)
        }
    }

    private func moveDay(_ offset: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = date
        }
    }
}
