import SwiftUI
import TreelabLanes

/// The queue of requests, oldest first, the shown one highlighted.
struct FeedQueueColumn: View {
    let model: LanesModel
    private let palette = HUDPalette()
    private let text = LanesText()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(verbatim: "\(text.queue) · \(model.requests.count)")
                    .font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(palette.cyan)
                Text(text.oldestFirst).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.requests) { request in
                        // A click, VoiceOver or any accessibility client's press selects it.
                        FeedQueueCard(request: request, selected: request.id == model.selectedRequest?.id)
                            .onTapGesture { model.select(request.id) }
                            .accessibilityAction { model.select(request.id) }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                KeyCap("↑↓"); Text(text.change).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                KeyCap("1 2 3"); Text(text.answerKey).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                KeyCap("↵"); Text(text.sendKey).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
    }
}

/// One request in the queue.
struct FeedQueueCard: View {
    let request: ClassifiedLane
    let selected: Bool
    private let palette = HUDPalette()
    private let text = LanesText()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusGlyph(.waitingForYou, size: 8)
                Text(text.kind(request.kind)).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(palette.amber)
                Spacer()
                if let since = request.record.waitingSince {
                    Text(FeedDuration.short(since: since)).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
            Text(verbatim: "\(request.record.project) › \(request.record.lane)")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
            Text(verbatim: request.record.reason)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.cardRaised : palette.card, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? palette.amber.opacity(0.8) : palette.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Durations and dates, written by the system in the user's language.
struct FeedDuration {
    /// "28 min", "3 h", "2 j" since a date.
    static func short(since date: Date, now: Date = Date()) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: max(60, now.timeIntervalSince(date))) ?? ""
    }

    /// "28 nov." for a wake date.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
