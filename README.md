# AFM

AFM mirrors the structure of Apple's [FoundationModels](https://developer.apple.com/documentation/FoundationModels) framework so
you can develop against familiar APIs even when the system frameworks aren't available. It lets you register custom model
providers, exercise them on Linux, and continue to bridge to the native implementations on Apple platforms where
`FoundationModels` ships.

## Highlights

- Drop-in `SystemLanguageModel`/`LanguageModelSession` scaffolding that copies the names and shapes of the Apple APIs while
  routing work to any model implementation you register.
- Codable transport types (`ChatMessage`, `ToolCall`, `ToolResult`, `TokenUsage`, and more) that round-trip with their
  `FoundationModels` counterparts when the framework is present.
- A `ChatModel` protocol and type-erased `AnyChatModel` helper for plugging in third-party or mock models.
- Tool metadata and invocation helpers that align with Apple’s tool calling model.
- Conditional adapter (`FoundationModelsChatAdapter`) that bridges directly into the native `FoundationModels` APIs on supported
  platforms.

## Usage

Add AFM as a dependency in your `Package.swift` file:

```swift
.package(url: "https://github.com/your-org/AFM.git", from: "1.0.0")
```

Register the model you want the default system session to use. This can point at a remote API, an in-process inference engine,
or a mock for tests:

```swift
import AFM

struct EchoChat: ChatModel {
    func complete(messages: [ChatMessage], options: GenerationOptions) async throws -> ChatResponse {
        let last = messages.last ?? .assistant("")
        if case let .text(text) = last.content {
            return ChatResponse(message: .assistant("Echo: \(text)"))
        }
        return ChatResponse(message: .assistant("Nothing to echo"))
    }
}

SystemLanguageModel.registerDefault {
    AnyChatModel(EchoChat())
}

let session = try LanguageModelSession()
let response = try await session.respond(prompt: Prompt("Hello"))
print(response.content) // "Echo: Hello"
```

You can also register named adapters and create sessions from them:

```swift
SystemLanguageModel.Adapter.registerCustom(name: "remote") {
    AnyChatModel(RemoteChatModel())
}

let adapter = SystemLanguageModel.Adapter(name: "remote")
let session = try LanguageModelSession(model: SystemLanguageModel(adapter: adapter))
```

### Declaring tools with the `@Tool` macro

FoundationModels ships a macro-based tool declaration system. AFM mirrors it so you can write identical definitions even when
the system framework is unavailable. Annotate a type that exposes a `callAsFunction` implementation and the macro will synthesize
the `ToolSpecification`, `invoke(_:)` bridge, and an `eraseToAnyTool()` helper.

```swift
@Tool(name: "echo", description: "Echoes text")
struct EchoTool {
    struct Input: Codable {
        let text: String
    }

    struct Output: Codable {
        let echoed: String
    }

    func callAsFunction(_ input: Input) async throws -> Output {
        Output(echoed: "Echo: \(input.text)")
    }
}

let tool = EchoTool().eraseToAnyTool()
let session = try LanguageModelSession(model: .default, tools: [tool])
```

The macro decodes incoming arguments into the `Input` type, forwards the request to your `callAsFunction` implementation, and
encodes the response as a `ToolResult`. If your implementation already returns `ToolResult`, the macro passes it through verbatim.

On Apple platforms that provide the FoundationModels framework you can swap in the adapter to reach the system models and bridge
data across the APIs:

```swift
#if canImport(FoundationModels)
import FoundationModels

let configuration = ChatConfiguration()
let options = GenerationOptions(configuration: configuration)

let chat = AnyChatModel(FoundationModelsChatAdapter())
let response = try await chat.complete(messages: [.user("Ping")], options: options)
let foundationResult = response.foundationResult()
#endif
```

The adapter remains unavailable when FoundationModels cannot be imported, so Linux builds keep working while you unit test
against mocks.

## Testing

Run the unit tests with:

```bash
swift test
```
