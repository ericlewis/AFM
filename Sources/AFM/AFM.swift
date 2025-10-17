import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Core conversational roles

public enum ChatRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Tool abstractions mirroring FoundationModels

public struct ToolCall: Codable, Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let argumentsJSON: String

    public init(identifier: String, name: String, argumentsJSON: String) {
        self.identifier = identifier
        self.name = name
        self.argumentsJSON = argumentsJSON
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationCall: FoundationModels.ToolCall) {
        self.init(identifier: foundationCall.identifier,
                  name: foundationCall.name,
                  argumentsJSON: foundationCall.argumentsJSON)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationCall: FoundationModels.ToolCall {
        FoundationModels.ToolCall(identifier: identifier,
                                  name: name,
                                  argumentsJSON: argumentsJSON)
    }
    #endif
}

public struct ToolResult: Codable, Hashable, Sendable {
    public let callIdentifier: String
    public let payloadJSON: String

    public init(callIdentifier: String, payloadJSON: String) {
        self.callIdentifier = callIdentifier
        self.payloadJSON = payloadJSON
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationResult: FoundationModels.ToolResult) {
        self.init(callIdentifier: foundationResult.callIdentifier,
                  payloadJSON: foundationResult.payloadJSON)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationResult: FoundationModels.ToolResult {
        FoundationModels.ToolResult(callIdentifier: callIdentifier,
                                    payloadJSON: payloadJSON)
    }
    #endif
}

// MARK: - Chat message representation

public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Content: Codable, Hashable, Sendable {
        case text(String)
        case toolInvocation(ToolCall)
        case toolResult(ToolResult)

        private enum CodingKeys: CodingKey {
            case type
            case value
        }

        private enum Kind: String, Codable {
            case text
            case toolInvocation
            case toolResult
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .type)
            switch kind {
            case .text:
                self = .text(try container.decode(String.self, forKey: .value))
            case .toolInvocation:
                self = .toolInvocation(try container.decode(ToolCall.self, forKey: .value))
            case .toolResult:
                self = .toolResult(try container.decode(ToolResult.self, forKey: .value))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .text(text):
                try container.encode(Kind.text, forKey: .type)
                try container.encode(text, forKey: .value)
            case let .toolInvocation(call):
                try container.encode(Kind.toolInvocation, forKey: .type)
                try container.encode(call, forKey: .value)
            case let .toolResult(result):
                try container.encode(Kind.toolResult, forKey: .type)
                try container.encode(result, forKey: .value)
            }
        }
    }

    public let role: ChatRole
    public let content: Content

    public init(role: ChatRole, content: Content) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: .text(text))
    }

    public static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: .text(text))
    }

    public static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: .text(text))
    }

    public static func toolInvocation(_ call: ToolCall) -> ChatMessage {
        ChatMessage(role: .assistant, content: .toolInvocation(call))
    }

    public static func toolResult(_ result: ToolResult) -> ChatMessage {
        ChatMessage(role: .tool, content: .toolResult(result))
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationMessage: FoundationModels.ChatMessage) {
        switch foundationMessage.content {
        case let .text(text):
            self.init(role: ChatRole(foundationRole: foundationMessage.role), content: .text(text))
        case let .toolInvocation(call):
            self.init(role: ChatRole(foundationRole: foundationMessage.role),
                      content: .toolInvocation(ToolCall(foundationCall: call)))
        case let .toolResult(result):
            self.init(role: ChatRole(foundationRole: foundationMessage.role),
                      content: .toolResult(ToolResult(foundationResult: result)))
        }
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationMessage: FoundationModels.ChatMessage {
        switch content {
        case let .text(text):
            return FoundationModels.ChatMessage(role: FoundationModels.ChatRole(role), content: .text(text))
        case let .toolInvocation(call):
            return FoundationModels.ChatMessage(role: FoundationModels.ChatRole(role),
                                                content: .toolInvocation(call.foundationCall))
        case let .toolResult(result):
            return FoundationModels.ChatMessage(role: FoundationModels.ChatRole(role),
                                                content: .toolResult(result.foundationResult))
        }
    }
    #endif
}

// MARK: - Prompt and instructions builders

public struct Instructions: Sendable, Hashable, Codable {
    public var segments: [String]

    public init(_ value: String) {
        self.segments = [value]
    }

    public init(segments: [String]) {
        self.segments = segments
    }

    public var text: String { segments.joined(separator: "\n") }
}

public protocol InstructionsRepresentable {
    func instructionsValue() -> Instructions
}

extension Instructions: InstructionsRepresentable {
    public func instructionsValue() -> Instructions { self }
}

extension String: InstructionsRepresentable {
    public func instructionsValue() -> Instructions { Instructions(self) }
}

@resultBuilder
public enum InstructionsBuilder {
    public static func buildBlock(_ components: InstructionsRepresentable...) -> Instructions {
        Instructions(segments: components.flatMap { $0.instructionsValue().segments })
    }

    public static func buildOptional(_ component: InstructionsRepresentable?) -> Instructions {
        component?.instructionsValue() ?? Instructions(segments: [])
    }

    public static func buildEither(first component: InstructionsRepresentable) -> Instructions {
        component.instructionsValue()
    }

    public static func buildEither(second component: InstructionsRepresentable) -> Instructions {
        component.instructionsValue()
    }

    public static func buildExpression(_ expression: InstructionsRepresentable) -> InstructionsRepresentable {
        expression
    }

    public static func buildArray(_ components: [InstructionsRepresentable]) -> Instructions {
        Instructions(segments: components.flatMap { $0.instructionsValue().segments })
    }

    public static func buildLimitedAvailability(_ component: InstructionsRepresentable) -> Instructions {
        component.instructionsValue()
    }
}

public struct Prompt: Sendable, Hashable, Codable {
    public struct Message: Sendable, Hashable, Codable {
        public let role: ChatRole
        public let content: String

        public init(role: ChatRole, content: String) {
            self.role = role
            self.content = content
        }
    }

    public var messages: [Message]

    public init(messages: [Message]) {
        self.messages = messages
    }

    public init(_ string: String) {
        self.messages = [.init(role: .user, content: string)]
    }
}

public protocol PromptRepresentable {
    func promptValue() -> Prompt
}

extension Prompt: PromptRepresentable {
    public func promptValue() -> Prompt { self }
}

extension String: PromptRepresentable {
    public func promptValue() -> Prompt { Prompt(self) }
}

@resultBuilder
public enum PromptBuilder {
    public static func buildBlock(_ components: PromptRepresentable...) -> Prompt {
        Prompt(messages: components.flatMap { $0.promptValue().messages })
    }

    public static func buildOptional(_ component: PromptRepresentable?) -> Prompt {
        component?.promptValue() ?? Prompt(messages: [])
    }

    public static func buildEither(first component: PromptRepresentable) -> Prompt {
        component.promptValue()
    }

    public static func buildEither(second component: PromptRepresentable) -> Prompt {
        component.promptValue()
    }

    public static func buildArray(_ components: [PromptRepresentable]) -> Prompt {
        Prompt(messages: components.flatMap { $0.promptValue().messages })
    }

    public static func buildLimitedAvailability(_ component: PromptRepresentable) -> Prompt {
        component.promptValue()
    }
}

public struct Transcript: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public let role: ChatRole
        public let content: GeneratedContent

        public init(role: ChatRole, content: GeneratedContent) {
            self.role = role
            self.content = content
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public mutating func append(_ entry: Entry) {
        entries.append(entry)
    }
}

// MARK: - Generated content conversions

public enum GeneratedContent: Sendable, Hashable, Codable {
    case text(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)

    init(from message: ChatMessage) {
        switch message.content {
        case let .text(text):
            self = .text(text)
        case let .toolInvocation(call):
            self = .toolCall(call)
        case let .toolResult(result):
            self = .toolResult(result)
        }
    }

    func toMessage(role: ChatRole) -> ChatMessage {
        switch self {
        case let .text(text):
            return ChatMessage(role: role, content: .text(text))
        case let .toolCall(call):
            return ChatMessage(role: role, content: .toolInvocation(call))
        case let .toolResult(result):
            return ChatMessage(role: role, content: .toolResult(result))
        }
    }
}

public protocol ConvertibleFromGeneratedContent {
    static func fromGeneratedContent(_ content: [GeneratedContent]) throws -> Self
}

public protocol ConvertibleToGeneratedContent {
    func asGeneratedContent() -> [GeneratedContent]
}

public typealias Generable = ConvertibleFromGeneratedContent & Sendable

extension String: ConvertibleFromGeneratedContent {
    public static func fromGeneratedContent(_ content: [GeneratedContent]) throws -> String {
        content.compactMap { item in
            if case let .text(text) = item { return text } else { return nil }
        }.joined(separator: "\n")
    }
}

extension Array: ConvertibleFromGeneratedContent where Element == GeneratedContent {
    public static func fromGeneratedContent(_ content: [GeneratedContent]) throws -> [GeneratedContent] {
        content
    }
}

// MARK: - Options and responses

public struct GenerationOptions: Codable, Hashable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maximumResponseTokens: Int?
    public var stopSequences: [String]
    public var tools: [ToolSpecification]

    public init(temperature: Double? = nil,
                topP: Double? = nil,
                maximumResponseTokens: Int? = nil,
                stopSequences: [String] = [],
                tools: [ToolSpecification] = []) {
        self.temperature = temperature
        self.topP = topP
        self.maximumResponseTokens = maximumResponseTokens
        self.stopSequences = stopSequences
        self.tools = tools
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(configuration: FoundationModels.ChatConfiguration) {
        self.init(temperature: configuration.temperature,
                  topP: configuration.topP,
                  maximumResponseTokens: configuration.maximumResponseTokens,
                  stopSequences: configuration.stopSequences,
                  tools: configuration.tools.map { ToolSpecification(foundationTool: $0) })
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationConfiguration: FoundationModels.ChatConfiguration {
        var configuration = FoundationModels.ChatConfiguration()
        configuration.temperature = temperature ?? configuration.temperature
        configuration.topP = topP ?? configuration.topP
        configuration.maximumResponseTokens = maximumResponseTokens ?? configuration.maximumResponseTokens
        configuration.stopSequences = stopSequences
        configuration.tools = tools.map { $0.foundationTool }
        return configuration
    }
    #endif
}

public struct ToolSpecification: Codable, Hashable, Sendable {
    public let name: String
    public let description: String?
    public let inputFormatJSONSchema: String?

    public init(name: String, description: String? = nil, inputFormatJSONSchema: String? = nil) {
        self.name = name
        self.description = description
        self.inputFormatJSONSchema = inputFormatJSONSchema
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationTool: FoundationModels.ChatConfiguration.Tool) {
        self.init(name: foundationTool.name,
                  description: foundationTool.description,
                  inputFormatJSONSchema: foundationTool.inputFormatJSONSchema)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationTool: FoundationModels.ChatConfiguration.Tool {
        FoundationModels.ChatConfiguration.Tool(name: name,
                                                description: description,
                                                inputFormatJSONSchema: inputFormatJSONSchema)
    }
    #endif
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public var totalTokens: Int { promptTokens + completionTokens }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationUsage: FoundationModels.ChatResult.Usage) {
        self.init(promptTokens: foundationUsage.promptTokens,
                  completionTokens: foundationUsage.completionTokens)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var foundationUsage: FoundationModels.ChatResult.Usage {
        FoundationModels.ChatResult.Usage(promptTokens: promptTokens,
                                          completionTokens: completionTokens)
    }
    #endif
}

public struct ChatResponse: Codable, Hashable, Sendable {
    public let message: ChatMessage
    public let additionalMessages: [ChatMessage]
    public let usage: TokenUsage?
    public let finishReason: String?

    public init(message: ChatMessage,
                additionalMessages: [ChatMessage] = [],
                usage: TokenUsage? = nil,
                finishReason: String? = nil) {
        self.message = message
        self.additionalMessages = additionalMessages
        self.usage = usage
        self.finishReason = finishReason
    }

    #if canImport(FoundationModels)
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationResult: FoundationModels.ChatResult) throws {
        guard let primary = foundationResult.messages.last else {
            throw FoundationModelWrapperError.emptyResponse
        }

        self.init(
            message: ChatMessage(foundationMessage: primary),
            additionalMessages: foundationResult.messages.dropLast().map { ChatMessage(foundationMessage: $0) },
            usage: foundationResult.usage.map { TokenUsage(foundationUsage: $0) },
            finishReason: foundationResult.finishReason
        )
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public func foundationResult() -> FoundationModels.ChatResult {
        var messages = additionalMessages.map { $0.foundationMessage }
        messages.append(message.foundationMessage)
        return FoundationModels.ChatResult(messages: messages,
                                            usage: usage.map { $0.foundationUsage },
                                            finishReason: finishReason)
    }
    #endif
}

// MARK: - Chat model abstraction

public protocol ChatModel {
    func complete(messages: [ChatMessage], options: GenerationOptions) async throws -> ChatResponse
}

public struct AnyChatModel: ChatModel {
    private let box: ([ChatMessage], GenerationOptions) async throws -> ChatResponse

    public init<M: ChatModel>(_ model: M) {
        self.box = model.complete
    }

    public init(box: @escaping ([ChatMessage], GenerationOptions) async throws -> ChatResponse) {
        self.box = box
    }

    public func complete(messages: [ChatMessage], options: GenerationOptions) async throws -> ChatResponse {
        try await box(messages, options)
    }
}

// MARK: - System language model scaffolding

public struct SystemLanguageModel {
    public struct UseCase: Sendable, Hashable, Codable {
        public let identifier: String

        public init(_ identifier: String) {
            self.identifier = identifier
        }

        public static let general = UseCase("general")
    }

    public struct Guardrails: Sendable, Hashable, Codable {
        public init() {}
    }

    public enum Availability: Sendable, Hashable, Codable {
        case available
        case unavailable(String)
    }

    private final class AdapterRegistry: @unchecked Sendable {
        private var storage: [String: () throws -> AnyChatModel] = [:]
        private let lock = NSLock()

        func register(name: String, factory: @escaping () throws -> AnyChatModel) {
            lock.lock()
            defer { lock.unlock() }
            storage[name] = factory
        }

        func factory(for name: String) -> (() throws -> AnyChatModel)? {
            lock.lock()
            defer { lock.unlock() }
            return storage[name]
        }
    }

    private final class DefaultModelRegistry: @unchecked Sendable {
        private var factory: (() throws -> AnyChatModel)?
        private let lock = NSLock()

        func set(_ factory: @escaping () throws -> AnyChatModel) {
            lock.lock()
            defer { lock.unlock() }
            self.factory = factory
        }

        func current() -> (() throws -> AnyChatModel)? {
            lock.lock()
            defer { lock.unlock() }
            return factory
        }
    }

    public struct Adapter {
        private static let registry = AdapterRegistry()

        public let identifier: String
        private let factory: () throws -> AnyChatModel

        public init(name: String) {
            if let factory = Adapter.registry.factory(for: name) {
                self.identifier = name
                self.factory = factory
            } else {
                self.identifier = name
                self.factory = {
                    throw FoundationModelWrapperError.adapterNotRegistered(name)
                }
            }
        }

        public init(fileURL: URL) {
            self.init(name: fileURL.lastPathComponent)
        }

        private init(identifier: String, factory: @escaping () throws -> AnyChatModel) {
            self.identifier = identifier
            self.factory = factory
        }

        public func makeModel() throws -> AnyChatModel {
            try factory()
        }

        public static func registerCustom(name: String,
                                          factory: @escaping () throws -> AnyChatModel) {
            registry.register(name: name, factory: factory)
        }

        public func compile() async throws {}
        public var creatorDefinedMetadata: [String: String] { [:] }

        public static func removeObsoleteAdapters() async throws {}

        public static func compatibleAdapterIdentifiers(name: String) -> [String] {
            Adapter.registry.factory(for: name) == nil ? [] : [name]
        }

        public func isCompatible(_ identifier: String) -> Bool {
            identifier == self.identifier
        }

        public enum AssetError: Error, Equatable {
            case notFound
            case incompatible
        }
    }

    private static let defaultRegistry = DefaultModelRegistry()

    private let factory: () throws -> AnyChatModel
    public let useCase: UseCase
    public let guardrails: Guardrails?
    public let availability: Availability
    public let supportedLanguages: [Locale]

    public init(useCase: UseCase = .general,
                guardrails: Guardrails? = nil,
                availability: Availability = .available,
                supportedLanguages: [Locale] = []) {
        self.useCase = useCase
        self.guardrails = guardrails
        self.availability = availability
        self.supportedLanguages = supportedLanguages
        self.factory = {
            guard let factory = Self.loadDefaultFactory() else {
                throw FoundationModelWrapperError.noDefaultModelRegistered
            }
            return try factory()
        }
    }

    public init(adapter: Adapter, guardrails: Guardrails? = nil,
                availability: Availability = .available,
                supportedLanguages: [Locale] = []) {
        self.useCase = .general
        self.guardrails = guardrails
        self.availability = availability
        self.supportedLanguages = supportedLanguages
        self.factory = {
            try adapter.makeModel()
        }
    }

    public func makeModel() throws -> AnyChatModel {
        try factory()
    }

    public var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    public func supportsLocale(_ locale: Locale) -> Bool {
        supportedLanguages.isEmpty || supportedLanguages.contains(where: { $0.identifier == locale.identifier })
    }

    public static func registerDefault(factory: @escaping () throws -> AnyChatModel) {
        defaultRegistry.set(factory)
    }

    private static func loadDefaultFactory() -> (() throws -> AnyChatModel)? {
        defaultRegistry.current()
    }

    public static var `default`: SystemLanguageModel {
        SystemLanguageModel()
    }
}

// MARK: - Language model session

public struct ToolInvocationContext: Sendable {
    public let call: ToolCall

    public init(call: ToolCall) {
        self.call = call
    }
}

public typealias ToolContext = ToolInvocationContext

public protocol Tool {
    var specification: ToolSpecification { get }
    func invoke(_ call: ToolCall) async throws -> ToolResult
}

public struct AnyTool: Tool {
    public let specification: ToolSpecification
    private let handler: (ToolCall) async throws -> ToolResult

    public init<T: Tool>(_ tool: T) {
        self.specification = tool.specification
        self.handler = tool.invoke
    }

    public init(_ tool: any Tool) {
        self.specification = tool.specification
        self.handler = { call in
            try await tool.invoke(call)
        }
    }

    public init(specification: ToolSpecification,
                handler: @escaping (ToolCall) async throws -> ToolResult) {
        self.specification = specification
        self.handler = handler
    }

    public func invoke(_ call: ToolCall) async throws -> ToolResult {
        try await handler(call)
    }
}

public enum LanguageModelFeedback: Sendable, Equatable {
    case positive
    case negative
    case neutral
}

public struct GeneratedContentAttachment: Sendable, Equatable {
    public let sentiment: LanguageModelFeedback
    public let issues: [String]
    public let desiredResponse: String?
    public let desiredText: String?
    public let desiredJSON: String?

    public init(sentiment: LanguageModelFeedback,
                issues: [String],
                desiredResponse: String? = nil,
                desiredText: String? = nil,
                desiredJSON: String? = nil) {
        self.sentiment = sentiment
        self.issues = issues
        self.desiredResponse = desiredResponse
        self.desiredText = desiredText
        self.desiredJSON = desiredJSON
    }
}

public final class LanguageModelSession: @unchecked Sendable {
    public enum GenerationError: Error, Equatable {
        case invalidResponse
        case toolNotFound
    }

    public enum ToolCallError: Error, Equatable {
        case missingCallIdentifier
        case invocationFailed
    }

    public struct Response<Content>: Sendable where Content: ConvertibleFromGeneratedContent & Sendable {
        public let content: Content
        public let generated: [GeneratedContent]
        public let usage: TokenUsage?

        public init(content: Content, generated: [GeneratedContent], usage: TokenUsage?) {
            self.content = content
            self.generated = generated
            self.usage = usage
        }
    }

    public struct ResponseStream<Content>: AsyncSequence where Content: ConvertibleFromGeneratedContent & Sendable {
        public typealias Element = Response<Content>
        private let stream: AsyncThrowingStream<Response<Content>, Error>

        init(stream: AsyncThrowingStream<Response<Content>, Error>) {
            self.stream = stream
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: AsyncThrowingStream<Response<Content>, Error>.AsyncIterator

            public mutating func next() async throws -> Response<Content>? {
                try await iterator.next()
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(iterator: stream.makeAsyncIterator())
        }
    }

    private let modelFactory: () throws -> AnyChatModel
    private var cachedModel: AnyChatModel?
    public private(set) var transcript: Transcript
    public private(set) var isResponding: Bool = false
    public let tools: [AnyTool]
    public let instructions: Instructions?

    private var feedbackAttachments: [GeneratedContentAttachment] = []

    public convenience init(model: SystemLanguageModel = .default,
                            tools: [any Tool] = [],
                            @InstructionsBuilder instructions: () throws -> Instructions = { Instructions(segments: []) }) rethrows {
        let built = try instructions()
        self.init(modelFactory: model.makeModel,
                  tools: tools.map { AnyTool($0) },
                  instructions: built.segments.isEmpty ? nil : built)
    }

    public convenience init(model: SystemLanguageModel = .default,
                            tools: [any Tool] = [],
                            instructions: Instructions?) throws {
        self.init(modelFactory: model.makeModel,
                  tools: tools.map { AnyTool($0) },
                  instructions: instructions)
    }

    public init(modelFactory: @escaping () throws -> AnyChatModel,
                tools: [AnyTool] = [],
                instructions: Instructions? = nil) {
        self.modelFactory = modelFactory
        self.tools = tools
        self.instructions = instructions
        self.transcript = Transcript()
    }

    private func resolveModel() throws -> AnyChatModel {
        if let model = cachedModel {
            return model
        }
        let newModel = try modelFactory()
        cachedModel = newModel
        return newModel
    }

    public func prewarm(promptPrefix: Prompt? = nil) async throws {
        guard let promptPrefix else { return }
        _ = try await respond(options: GenerationOptions(), prompt: promptPrefix)
    }

    public func respond(options: GenerationOptions = GenerationOptions(),
                        @PromptBuilder prompt: () -> Prompt) async throws -> Response<String> {
        try await respond(options: options, prompt: prompt())
    }

    public func respond(options: GenerationOptions = GenerationOptions(),
                        prompt: Prompt) async throws -> Response<String> {
        try await respond(to: prompt, options: options)
    }

    public func respond(to prompt: Prompt,
                        options: GenerationOptions = GenerationOptions()) async throws -> Response<String> {
        try await respond(to: prompt, generating: String.self, includeSchemaInPrompt: false, options: options)
    }

    public func respond<Content>(to prompt: Prompt,
                                 generating type: Content.Type,
                                 includeSchemaInPrompt: Bool = false,
                                 options: GenerationOptions = GenerationOptions()) async throws -> Response<Content> where Content: ConvertibleFromGeneratedContent {
        let promptEntries = prompt.messages.map { Transcript.Entry(role: $0.role, content: .text($0.content)) }
        let historyEntries = transcript.entries + promptEntries

        var messages = instructions.map { [ChatMessage.system($0.text)] } ?? []
        messages.append(contentsOf: historyEntries.map { $0.content.toMessage(role: $0.role) })

        let model = try resolveModel()
        isResponding = true
        defer { isResponding = false }

        var configuredOptions = options
        if !tools.isEmpty {
            configuredOptions.tools = tools.map { $0.specification }
        }

        let response = try await model.complete(messages: messages, options: configuredOptions)
        let generated = [GeneratedContent(from: response.message)] + response.additionalMessages.map(GeneratedContent.init(from:))

        let content = try Content.fromGeneratedContent(generated)
        promptEntries.forEach { transcript.append($0) }
        let transcriptEntry = Transcript.Entry(role: response.message.role, content: GeneratedContent(from: response.message))

        transcript.append(transcriptEntry)

        return Response(content: content, generated: generated, usage: response.usage)
    }

    public func respond<Content>(options: GenerationOptions = GenerationOptions(),
                                 generating type: Content.Type,
                                 includeSchemaInPrompt: Bool = false,
                                 prompt: Prompt) async throws -> Response<Content> where Content: ConvertibleFromGeneratedContent {
        try await respond(to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
    }

    public func respond<Content>(generating type: Content.Type,
                                 includeSchemaInPrompt: Bool = false,
                                 options: GenerationOptions = GenerationOptions(),
                                 @PromptBuilder prompt: () -> Prompt) async throws -> Response<Content> where Content: ConvertibleFromGeneratedContent {
        try await respond(to: prompt(), generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
    }

    public func streamResponse(options: GenerationOptions = GenerationOptions(),
                               prompt: Prompt) -> ResponseStream<String> {
        streamResponse(to: prompt, generating: String.self, includeSchemaInPrompt: false, options: options)
    }

    public func streamResponse<Content>(options: GenerationOptions = GenerationOptions(),
                                        prompt: Prompt,
                                        generating type: Content.Type,
                                        includeSchemaInPrompt: Bool = false) -> ResponseStream<Content> where Content: ConvertibleFromGeneratedContent {
        streamResponse(to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
    }

    public func streamResponse<Content>(to prompt: Prompt,
                                        generating type: Content.Type,
                                        includeSchemaInPrompt: Bool = false,
                                        options: GenerationOptions = GenerationOptions()) -> ResponseStream<Content> where Content: ConvertibleFromGeneratedContent {
        ResponseStream(stream: AsyncThrowingStream { continuation in
            Task {
                do {
                    let response: Response<Content> = try await self.respond(to: prompt,
                                                                              generating: type,
                                                                              includeSchemaInPrompt: includeSchemaInPrompt,
                                                                              options: options)
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        })
    }

    public func logFeedbackAttachment(sentiment: LanguageModelFeedback,
                                       issues: [String],
                                       desiredResponseContent: PromptRepresentable?) {
        feedbackAttachments.append(GeneratedContentAttachment(sentiment: sentiment,
                                                              issues: issues,
                                                              desiredResponse: desiredResponseContent?.promptValue().messages.map { $0.content }.joined(separator: "\n")))
    }

    public func logFeedbackAttachment(sentiment: LanguageModelFeedback,
                                       issues: [String],
                                       desiredResponseText: String?) {
        feedbackAttachments.append(GeneratedContentAttachment(sentiment: sentiment,
                                                              issues: issues,
                                                              desiredText: desiredResponseText))
    }

    public func logFeedbackAttachment(sentiment: LanguageModelFeedback,
                                       issues: [String],
                                       desiredOutput: GeneratedContent?) {
        feedbackAttachments.append(GeneratedContentAttachment(sentiment: sentiment,
                                                              issues: issues,
                                                              desiredJSON: desiredOutput?.asJSON()))
    }
}

private extension GeneratedContent {
    func asJSON() -> String? {
        switch self {
        case let .text(text):
            guard let data = try? JSONEncoder().encode(["text": text]) else { return nil }
            return String(data: data, encoding: .utf8)
        case let .toolCall(call):
            let dictionary: [String: String] = ["identifier": call.identifier,
                                                "name": call.name,
                                                "argumentsJSON": call.argumentsJSON]
            guard let data = try? JSONEncoder().encode(dictionary) else { return nil }
            return String(data: data, encoding: .utf8)
        case let .toolResult(result):
            let dictionary: [String: String] = ["callIdentifier": result.callIdentifier,
                                                "payloadJSON": result.payloadJSON]
            guard let data = try? JSONEncoder().encode(dictionary) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}

// MARK: - Legacy error namespace

public enum FoundationModelWrapperError: Error, Equatable {
    case invalidToolArguments
    case toolResponseMismatch
    case emptyResponse
    case adapterNotRegistered(String)
    case noDefaultModelRegistered
}

// MARK: - Conditional bridging helpers

#if canImport(FoundationModels)
@available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
public struct FoundationModelsChatAdapter: ChatModel {
    private let session: ChatSession

    public init(session: ChatSession = ChatSession()) {
        self.session = session
    }

    public func complete(messages: [ChatMessage], options: GenerationOptions) async throws -> ChatResponse {
        let fmMessages = messages.map { $0.foundationMessage }
        let response = try await session.complete(messages: fmMessages,
                                                  configuration: options.foundationConfiguration)
        return try ChatResponse(foundationResult: response)
    }
}

extension FoundationModels.ChatMessage {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(afmMessage message: ChatMessage) {
        switch message.content {
        case let .text(text):
            self.init(role: FoundationModels.ChatRole(message.role), content: .text(text))
        case let .toolInvocation(call):
            self.init(role: FoundationModels.ChatRole(message.role),
                      content: .toolInvocation(call.foundationCall))
        case let .toolResult(result):
            self.init(role: FoundationModels.ChatRole(message.role),
                      content: .toolResult(result.foundationResult))
        }
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var afmMessage: ChatMessage {
        ChatMessage(foundationMessage: self)
    }
}

extension ChatRole {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(foundationRole role: FoundationModels.ChatRole) {
        switch role {
        case .system: self = .system
        case .user: self = .user
        case .assistant: self = .assistant
        case .tool: self = .tool
        @unknown default:
            self = .assistant
        }
    }
}

extension FoundationModels.ChatRole {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(_ role: ChatRole) {
        switch role {
        case .system: self = .system
        case .user: self = .user
        case .assistant: self = .assistant
        case .tool: self = .tool
        }
    }
}

extension FoundationModels.ToolCall {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(afmCall: ToolCall) {
        self.init(identifier: afmCall.identifier,
                  name: afmCall.name,
                  argumentsJSON: afmCall.argumentsJSON)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var afmCall: ToolCall { ToolCall(foundationCall: self) }
}

extension FoundationModels.ToolResult {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(afmResult: ToolResult) {
        self.init(callIdentifier: afmResult.callIdentifier,
                  payloadJSON: afmResult.payloadJSON)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var afmResult: ToolResult { ToolResult(foundationResult: self) }
}

extension FoundationModels.ChatConfiguration.Tool {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(afmSpecification: ToolSpecification) {
        self.init(name: afmSpecification.name,
                  description: afmSpecification.description,
                  inputFormatJSONSchema: afmSpecification.inputFormatJSONSchema)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public var afmSpecification: ToolSpecification { ToolSpecification(foundationTool: self) }
}
#endif
