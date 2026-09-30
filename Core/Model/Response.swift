import Foundation

/// What finishing an item records beyond the fact that it happened.
///
/// A weigh-in is a task whose answer is a number; a journal prompt is one
/// whose answer is a sentence. The engine treats all three the same — it is
/// the app that decides which keyboard to put up — so nothing downstream has
/// to know which kind an item is.
nonisolated enum ResponseKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Done is the whole answer.
    case none
    case number
    case text

    var id: String { rawValue }

    var asksForAnything: Bool { self != .none }
}
