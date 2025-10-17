import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum ToolMacroMessage: String, DiagnosticMessage {
    case unsupportedDeclaration = "@Tool can only be applied to classes, actors, or structures"
    case missingCallAsFunction = "@Tool requires a callAsFunction implementation"
    case unsupportedParameterCount = "@Tool supports at most one argument parameter and an optional ToolInvocationContext"
    case missingParameterType = "@Tool requires the parameter to have an explicit type"
    case unsupportedContextParameter = "The second parameter must be ToolInvocationContext"

    var message: String { rawValue }
    var diagnosticID: MessageID { MessageID(domain: "AFM.ToolMacro", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

struct ToolMacroDiagnostics {
    static func diagnose(_ message: ToolMacroMessage, on node: Syntax, in context: some MacroExpansionContext) {
        context.diagnose(Diagnostic(node: node, message: message))
    }
}

public struct ToolMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) || declaration.is(StructDeclSyntax.self) || declaration.is(ActorDeclSyntax.self) else {
            ToolMacroDiagnostics.diagnose(.unsupportedDeclaration, on: Syntax(declaration), in: context)
            return []
        }

        guard let callFunction = declaration.memberBlock.members.compactMap({ member -> FunctionDeclSyntax? in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            return function.name.text == "callAsFunction" ? function : nil
        }).first else {
            ToolMacroDiagnostics.diagnose(.missingCallAsFunction, on: Syntax(declaration), in: context)
            return []
        }

        let parameters = callFunction.signature.parameterClause.parameters
        if parameters.count > 2 {
            ToolMacroDiagnostics.diagnose(.unsupportedParameterCount, on: Syntax(callFunction), in: context)
            return []
        }

        var parameterTypeName: String?
        var argumentLabel: String?
        if let parameter = parameters.first {
            let typeSyntax = parameter.type
            let trimmedType = typeSyntax.trimmedDescription
            if trimmedType.isEmpty {
                ToolMacroDiagnostics.diagnose(.missingParameterType, on: Syntax(parameter), in: context)
                return []
            }
            parameterTypeName = trimmedType
            let firstName = parameter.firstName
            if !firstName.text.isEmpty && firstName.text != "_" {
                argumentLabel = firstName.text
            }
        }

        var includeContext = false
        var contextLabel: String?
        if parameters.count == 2, let contextParameter = parameters.last {
            let contextTypeSyntax = contextParameter.type
            let trimmedContextType = contextTypeSyntax.trimmedDescription
            if trimmedContextType.isEmpty {
                ToolMacroDiagnostics.diagnose(.missingParameterType, on: Syntax(contextParameter), in: context)
                return []
            }
            let contextTypeName = trimmedContextType
            let validContextNames = [
                "ToolInvocationContext",
                "AFM.ToolInvocationContext",
                "FoundationModels.ToolInvocationContext",
                "ToolContext",
                "AFM.ToolContext",
                "FoundationModels.ToolContext"
            ]
            guard validContextNames.contains(where: { contextTypeName.hasSuffix($0) }) else {
                ToolMacroDiagnostics.diagnose(.unsupportedContextParameter, on: Syntax(contextParameter), in: context)
                return []
            }
            includeContext = true
            let contextFirstName = contextParameter.firstName
            if !contextFirstName.text.isEmpty && contextFirstName.text != "_" {
                contextLabel = contextFirstName.text
            }
        }

        let nameExpr: ExprSyntax
        let descriptionExpr: ExprSyntax
        let schemaExpr: ExprSyntax
        if let args = node.arguments?.as(LabeledExprListSyntax.self), !args.isEmpty {
            var parsedName: ExprSyntax?
            var parsedDescription: ExprSyntax?
            var parsedSchema: ExprSyntax?
            for argument in args {
                let label = argument.label?.text ?? ""
                if label == "name" || ((label.isEmpty || label == "_") && parsedName == nil) {
                    parsedName = argument.expression
                    continue
                }
                if label == "description" {
                    parsedDescription = argument.expression
                    continue
                }
                if label == "inputFormatJSONSchema" || label == "schema" {
                    parsedSchema = argument.expression
                }
            }
            nameExpr = parsedName ?? ExprSyntax(StringLiteralExprSyntax(content: declaration.identifierText))
            descriptionExpr = parsedDescription ?? ExprSyntax(NilLiteralExprSyntax())
            schemaExpr = parsedSchema ?? ExprSyntax(NilLiteralExprSyntax())
        } else {
            nameExpr = ExprSyntax(StringLiteralExprSyntax(content: declaration.identifierText))
            descriptionExpr = ExprSyntax(NilLiteralExprSyntax())
            schemaExpr = ExprSyntax(NilLiteralExprSyntax())
        }

        let specDecl: DeclSyntax = """
        public static var toolSpecification: ToolSpecification {
            ToolSpecification(name: \(nameExpr), description: \(descriptionExpr), inputFormatJSONSchema: \(schemaExpr))
        }
        """

        let instanceSpecDecl: DeclSyntax = """
        public var specification: ToolSpecification { Self.toolSpecification }
        """

        let tryKeyword = callFunction.signature.effectSpecifiers?.throwsSpecifier != nil ? "try" : nil
        let awaitKeyword = callFunction.signature.effectSpecifiers?.asyncSpecifier != nil ? "await" : nil
        let invocationPrefix = [tryKeyword, awaitKeyword].compactMap { $0 }.joined(separator: " ")
        let callSuffix: String
        if includeContext {
            let contextArgument = (contextLabel.map { "\($0): ToolInvocationContext(call: call)" }) ?? "ToolInvocationContext(call: call)"
            if parameterTypeName != nil {
                let argument = (argumentLabel.map { "\($0): arguments" }) ?? "arguments"
                callSuffix = "\(argument), \(contextArgument)"
            } else {
                callSuffix = contextArgument
            }
        } else if parameterTypeName != nil {
            callSuffix = (argumentLabel.map { "\($0): arguments" }) ?? "arguments"
        } else {
            callSuffix = ""
        }

        let callExpression: String
        if callSuffix.isEmpty {
            callExpression = "callAsFunction()"
        } else {
            callExpression = "callAsFunction(\(callSuffix))"
        }

        let prefixedCallExpression: String
        if invocationPrefix.isEmpty {
            prefixedCallExpression = callExpression
        } else {
            prefixedCallExpression = "\(invocationPrefix) \(callExpression)"
        }

        let decodeStatements: DeclSyntax
        if let parameterTypeName {
            decodeStatements = """
            let decoder = JSONDecoder()
            let trimmedJSON = call.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonData = trimmedJSON.isEmpty ? Foundation.Data("{}".utf8) : Foundation.Data(trimmedJSON.utf8)
            let arguments: \(raw: parameterTypeName)
            do {
                arguments = try decoder.decode(\(raw: parameterTypeName).self, from: jsonData)
            } catch {
                throw FoundationModelWrapperError.invalidToolArguments
            }
            """
        } else {
            decodeStatements = ""
        }

        let returnType = callFunction.signature.returnClause?.type.trimmedDescription ?? "Void"
        let loweredReturnType = returnType.replacingOccurrences(of: " ", with: "")
        let bodyStatements: DeclSyntax
        if loweredReturnType == "Void" || loweredReturnType == "()" {
            bodyStatements = """
            \(decodeStatements)
            \(raw: prefixedCallExpression)
            return ToolResult(callIdentifier: call.identifier, payloadJSON: "{}")
            """
        } else if loweredReturnType.hasSuffix("ToolResult") {
            bodyStatements = """
            \(decodeStatements)
            let result = \(raw: prefixedCallExpression)
            return result
            """
        } else {
            bodyStatements = """
            \(decodeStatements)
            let output = \(raw: prefixedCallExpression)
            let encoder = JSONEncoder()
            let payloadJSON: String
            do {
                let payloadData = try encoder.encode(output)
                guard let encoded = String(data: payloadData, encoding: .utf8) else {
                    throw FoundationModelWrapperError.toolResponseMismatch
                }
                payloadJSON = encoded
            } catch {
                throw FoundationModelWrapperError.toolResponseMismatch
            }
            return ToolResult(callIdentifier: call.identifier, payloadJSON: payloadJSON)
            """
        }

        let invokeDecl: DeclSyntax = """
        public func invoke(_ call: ToolCall) async throws -> ToolResult {
            \(bodyStatements)
        }
        """

        let eraseDecl: DeclSyntax = """
        public func eraseToAnyTool() -> AnyTool {
            AnyTool(specification: Self.toolSpecification) { call in
                try await self.invoke(call)
            }
        }
        """

        return [specDecl, instanceSpecDecl, invokeDecl, eraseDecl]
    }
}

extension ToolMacro {
    public static func expansion(of node: AttributeSyntax,
                                 attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        let extensionDecl: DeclSyntax = """
        extension \(type.trimmed): Tool {}
        """
        guard let ext = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [ext]
    }
}

@main
struct AFMMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ToolMacro.self
    ]
}

private extension DeclGroupSyntax {
    var identifierText: String {
        if let decl = self.as(ClassDeclSyntax.self) {
            return decl.name.text
        }
        if let decl = self.as(StructDeclSyntax.self) {
            return decl.name.text
        }
        if let decl = self.as(ActorDeclSyntax.self) {
            return decl.name.text
        }
        return "Tool"
    }
}
