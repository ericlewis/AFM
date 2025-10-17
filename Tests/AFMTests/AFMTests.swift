import Foundation
import XCTest
@testable import AFM

final class ChatMessageCodableTests: XCTestCase {
    func testEncodesAndDecodesToolMessages() throws {
        let messages: [ChatMessage] = [
            .system("Helper instructions"),
            .user("Calculate the area of a circle"),
            .toolInvocation(.init(identifier: "1", name: "area", argumentsJSON: "{\"radius\": 5}")),
            .toolResult(.init(callIdentifier: "1", payloadJSON: "{\"area\": 78.5}")),
            .assistant("The area is about 78.5 square units.")
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(messages)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ChatMessage].self, from: data)
        XCTAssertEqual(decoded, messages)
    }
}

final class AnyChatModelTests: XCTestCase {
    func testTypeErasureForwardsCalls() async throws {
        let expectation = expectation(description: "completion invoked")
        let mock = MockChatModel { messages, options in
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first, .user("Hello"))
            XCTAssertEqual(options.temperature, 0.2)
            XCTAssertEqual(options.stopSequences, ["--"])
            expectation.fulfill()
            return ChatResponse(message: .assistant("Hi there"),
                                 usage: TokenUsage(promptTokens: 5, completionTokens: 8))
        }

        let erased = AnyChatModel(mock)
        let response = try await erased.complete(messages: [.user("Hello")],
                                                 options: .init(temperature: 0.2, stopSequences: ["--"]))

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(response.message, .assistant("Hi there"))
        XCTAssertEqual(response.usage?.totalTokens, 13)
    }
}

final class LanguageModelSessionTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        SystemLanguageModel.registerDefault {
            AnyChatModel { messages, _ in
                let last = messages.last ?? .assistant("")
                return ChatResponse(message: .assistant("Echo: \((last.content.valueText ?? ""))"))
            }
        }
    }

    func testRespondUsesRegisteredDefaultModel() async throws {
        let session = try LanguageModelSession()
        let response = try await session.respond(prompt: Prompt("Hi"))
        XCTAssertEqual(response.content, "Echo: Hi")
        XCTAssertFalse(session.transcript.entries.isEmpty)
    }
}

@Tool(name: "echo", description: "Echoes text")
private struct EchoToolDefinition {
    struct Input: Codable, Equatable {
        let text: String
    }

    struct Output: Codable, Equatable {
        let echoed: String
    }

    func callAsFunction(_ arguments: Input) async throws -> Output {
        Output(echoed: "Echo: \(arguments.text)")
    }
}

final class ToolMacroTests: XCTestCase {
    func testGeneratedSpecificationMatchesMetadata() {
        XCTAssertEqual(EchoToolDefinition.toolSpecification.name, "echo")
        XCTAssertEqual(EchoToolDefinition.toolSpecification.description, "Echoes text")
    }

    func testInvokeEncodesReturnPayload() async throws {
        let tool = EchoToolDefinition()
        let call = ToolCall(identifier: "1", name: "echo", argumentsJSON: "{\"text\":\"Hi\"}")
        let result = try await tool.invoke(call)
        XCTAssertEqual(result.callIdentifier, "1")

        let payload = try JSONDecoder().decode(EchoToolDefinition.Output.self, from: Data(result.payloadJSON.utf8))
        XCTAssertEqual(payload, .init(echoed: "Echo: Hi"))
    }

    func testEraseToAnyToolProducesSpecification() {
        let erased = EchoToolDefinition().eraseToAnyTool()
        XCTAssertEqual(erased.specification, EchoToolDefinition.toolSpecification)
    }
}

final class TokenUsageTests: XCTestCase {
    func testTotalTokens() {
        let usage = TokenUsage(promptTokens: 42, completionTokens: 8)
        XCTAssertEqual(usage.totalTokens, 50)
    }
}

private struct MockChatModel: ChatModel {
    let handler: @Sendable ([ChatMessage], GenerationOptions) async throws -> ChatResponse

    init(handler: @escaping @Sendable ([ChatMessage], GenerationOptions) async throws -> ChatResponse) {
        self.handler = handler
    }

    func complete(messages: [ChatMessage], options: GenerationOptions) async throws -> ChatResponse {
        try await handler(messages, options)
    }
}

private extension ChatMessage.Content {
    var valueText: String? {
        switch self {
        case let .text(text):
            return text
        case .toolInvocation, .toolResult:
            return nil
        }
    }
}
