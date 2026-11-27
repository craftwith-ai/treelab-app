import SwiftUI
import TreelabLanes

/// Stopped lanes with "Relaunch", working lanes, and lanes outside the counter (never relaunched here).
struct FeedSideColumn: View {
    let model: LanesModel
    private let palette = HUDPalette()
    private let text = LanesText()

    var body: some View {
        let snapshot = model.state.snapshot
        let stopped = snapshot.lanes(.stopped)
        let working = snapshot.lanes(.working)
        let off = snapshot.lanes(.offCounter)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section(text.stoppedSection, stopped.count)
                ForEach(stopped) { lane in
                    HStack(alignment: .center, spacing: 8) {
                        StatusGlyph(.stopped, size: 8)
                        laneLabel(lane)
                        Spacer(minLength: 4)
                        Button(text.relaunch) { Task { await model.relaunch(lane) } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.cyan)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(palette.lineBright))
                            .disabled(model.busyLaneIDs.contains(lane.id))
                    }
                    .padding(8)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(text.nothingRestarts).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                section(text.workingSection, working.count).padding(.top, 8)
                ForEach(working) { lane in
                    HStack(spacing: 8) { StatusGlyph(.working, size: 8); laneLabel(lane) }
                }
                section(text.offCounterSection, off.count).padding(.top, 8)
                ForEach(off) { lane in
                    HStack(spacing: 8) {
                        StatusGlyph(.offCounter, size: 8)
                        laneLabel(lane)
                        Spacer(minLength: 4)
                        if let wake = lane.record.wakeAt, lane.record.waitsFor == "date" {
                            Text(text.backOn(FeedDuration.day(wake))).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        } else if lane.record.permanent {
                            Text(text.permanentLane).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func section(_ title: String, _ count: Int) -> some View {
        Text(verbatim: "\(title) · \(count)").font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(palette.textSecondary)
    }

    private func laneLabel(_ lane: ClassifiedLane) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "\(lane.record.project) › \(lane.record.lane)").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
            if !lane.record.reason.isEmpty {
                Text(verbatim: lane.record.reason).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
        }
    }
}
