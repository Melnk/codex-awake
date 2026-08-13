import Foundation

public struct CodexReasoningOption: Equatable, Sendable {
    public let id: String
    public let description: String

    public init(id: String, description: String) {
        self.id = id
        self.description = description
    }
}

public struct CodexModelOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String
    public let isDefault: Bool
    public let defaultReasoningEffort: String
    public let reasoningOptions: [CodexReasoningOption]

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        isDefault: Bool,
        defaultReasoningEffort: String,
        reasoningOptions: [CodexReasoningOption]
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.isDefault = isDefault
        self.defaultReasoningEffort = defaultReasoningEffort
        self.reasoningOptions = reasoningOptions
    }
}
