/// What a lane asks, word for word, from `lab ginkgo question`.
public enum LabQuestion: Sendable, Equatable {
    /// A question box (several questions, each with numbered choices).
    case box(qid: String, items: [Item])
    /// The end of the last message of a session that waits.
    case message(String)
    /// Nothing waits.
    case none

    /// One question of a box.
    public struct Item: Sendable, Equatable, Identifiable {
        /// Its number in the box, from 1.
        public var number: Int
        /// The question text.
        public var text: String
        /// Its choices, numbered from 1.
        public var options: [Option]
        /// Several choices allowed.
        public var multiple: Bool
        /// The recommended choice, as lab wrote it.
        public var recommended: String?

        /// The number.
        public var id: Int { number }

        /// Creates an item.
        /// - Parameters:
        ///   - number: its number.
        ///   - text: the question.
        ///   - options: the choices.
        ///   - multiple: several choices allowed.
        ///   - recommended: the recommended choice.
        public init(number: Int, text: String, options: [Option], multiple: Bool, recommended: String?) {
            self.number = number
            self.text = text
            self.options = options
            self.multiple = multiple
            self.recommended = recommended
        }
    }

    /// One choice.
    public struct Option: Sendable, Equatable, Identifiable {
        /// Its number, from 1 (the key to press).
        public var number: Int
        /// Its label.
        public var label: String
        /// Its description.
        public var detail: String

        /// The number.
        public var id: Int { number }

        /// Creates a choice.
        /// - Parameters:
        ///   - number: its number.
        ///   - label: its label.
        ///   - detail: its description.
        public init(number: Int, label: String, detail: String) {
            self.number = number
            self.label = label
            self.detail = detail
        }
    }

    /// Reads the output of `lab ginkgo question`.
    /// - Parameter block: the output's block.
    /// - Returns: the question; unknown shapes read as ``none``.
    public static func parse(_ block: KeyValueBlock) -> LabQuestion {
        switch block.first("WAITS") {
        case "box":
            guard let qid = block.first("QID"), !qid.isEmpty else { return .none }
            var items: [Item] = []
            var number = 1
            while let text = block.first("QUESTION_\(number)") {
                var options: [Option] = []
                var choice = 1
                while let label = block.first("OPTION_\(number)_\(choice)") {
                    options.append(Option(number: choice, label: label, detail: block.first("DESC_\(number)_\(choice)") ?? ""))
                    choice += 1
                }
                items.append(Item(
                    number: number,
                    text: text,
                    options: options,
                    multiple: block.first("MULTI_\(number)") == "yes" || block.first("MULTI_\(number)") == "true",
                    recommended: block.first("RECOMMENDED_\(number)")
                ))
                number += 1
            }
            return items.isEmpty ? .none : .box(qid: qid, items: items)
        case "message":
            return .message(block.first("MESSAGE") ?? "")
        default:
            return .none
        }
    }
}
