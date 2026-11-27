import SwiftUI
import TreelabLanes

/// The current request in large: kind, lane, lab's reason, what the lane asks word for word,
/// the numbered choices (keys 1 to 9), a free answer, "Open the lane", and the outcome.
struct FeedRequestDetail: View {
    @Bindable var model: LanesModel
    @FocusState private var answerFocused: Bool
    @FocusState private var detailFocused: Bool
    private let palette = HUDPalette()
    private let text = LanesText()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let request = model.selectedRequest {
                    header(request)
                    Text(verbatim: request.record.reason)
                        .font(.system(size: 14)).foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(palette.line).frame(height: 1)
                    questionSection(request)
                    answerField(request)
                    footer(request)
                } else {
                    Text(text.empty)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .focusable()
        .focusEffectDisabled()
        .focused($detailFocused)
        .onAppear { detailFocused = true }
        .onKeyPress(characters: .decimalDigits) { press in
            guard !answerFocused, let digit = Int(press.characters), digit > 0 else { return .ignored }
            return model.pressDigit(digit) ? .handled : .ignored
        }
    }

    private func header(_ request: ClassifiedLane) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusGlyph(.waitingForYou, size: 10)
                Text(text.kind(request.kind)).font(.system(size: 12, weight: .bold)).tracking(1.5).foregroundStyle(palette.amber)
                if let since = request.record.waitingSince {
                    Text(text.waitingSince(FeedDuration.short(since: since))).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if let index = model.requests.firstIndex(of: request) {
                    Text(verbatim: "\(index + 1) / \(model.requests.count)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(request.record.project) › \(request.record.lane)")
                    .font(.system(size: 22, weight: .semibold))
                if !request.record.batch.isEmpty {
                    Text(verbatim: request.record.batch).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func questionSection(_ request: ClassifiedLane) -> some View {
        if model.isReadingQuestion && model.questionLaneID != request.id {
            Text(text.readingQuestion).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        } else {
            switch model.question {
            case let .box(_, items) where model.questionLaneID == request.id:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in questionItem(item) }
                    if items.count > 1 || items.contains(where: \.multiple) {
                        HStack {
                            Text(text.chooseThenSend).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                            Spacer()
                            actionButton(text.send, key: "↵", prominent: true, disabled: model.picks.values.allSatisfy(\.isEmpty) || isBusy(request)) {
                                Task { await model.submit() }
                            }
                        }
                    }
                }
            case let .message(message) where model.questionLaneID == request.id:
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.lastMessage).font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(palette.cyan)
                    Text(verbatim: message).font(.system(size: 13, design: .monospaced)).foregroundStyle(palette.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            default:
                Text(text.noQuestion).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func questionItem(_ item: LabQuestion.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.text).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(item.options) { option in
                let chosen = model.picks[item.number]?.contains(option.number) == true
                Button {
                    model.pick(question: item.number, option: option.number)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        KeyCap("\(option.number)")
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(verbatim: option.label).font(.system(size: 13, weight: .semibold))
                                if item.recommended == "\(option.number)" || item.recommended == option.label {
                                    Text(text.recommended).font(.system(size: 10)).foregroundStyle(palette.cyan)
                                }
                            }
                            if !option.detail.isEmpty {
                                Text(verbatim: option.detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(chosen ? palette.cardRaised : palette.card, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(chosen ? palette.cyan : palette.lineBright))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.selectedRequest.map(isBusy) ?? true)
            }
        }
    }

    private func answerField(_ request: ClassifiedLane) -> some View {
        HStack(spacing: 8) {
            TextField(text.answerPlaceholder, text: $model.draftAnswer)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($answerFocused)
                .onSubmit(sendText)
                .padding(10)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.lineBright))
            actionButton(text.send, key: "↵", prominent: false, disabled: model.draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy(request), action: sendText)
        }
    }

    private func footer(_ request: ClassifiedLane) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                actionButton(text.openLane, key: nil, prominent: false, disabled: isBusy(request)) {
                    Task { await model.open(request) }
                }
                Spacer()
                if let next = nextRequest(after: request) {
                    Text(text.nextRequest).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(palette.textSecondary)
                    Text(text.kind(next.kind)).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.amber)
                    Text(verbatim: "\(next.record.project) › \(next.record.lane)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            if let notice = model.notice {
                let refused = { if case .refused = notice { return true } else { return false } }()
                Text(text.notice(notice))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(refused ? palette.red : palette.cyan)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func actionButton(_ title: String, key: String?, prominent: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let key { KeyCap(key) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(disabled ? palette.textSecondary : palette.cyan)
            .background(prominent ? palette.buttonFill : palette.card, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(prominent ? palette.cyan : palette.lineBright))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func sendText() {
        Task { await model.submitDraft() }
    }

    private func isBusy(_ request: ClassifiedLane) -> Bool { model.busyLaneIDs.contains(request.id) }

    private func nextRequest(after request: ClassifiedLane) -> ClassifiedLane? {
        guard let index = model.requests.firstIndex(of: request), index + 1 < model.requests.count else { return nil }
        return model.requests[index + 1]
    }
}
