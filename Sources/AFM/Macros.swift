#if swift(>=5.9) && !canImport(FoundationModels)
@attached(member, names: named(toolSpecification), named(specification), named(invoke(_:)), named(eraseToAnyTool))
@attached(extension, conformances: Tool)
public macro Tool(name: String? = nil,
                  description: String? = nil,
                  inputFormatJSONSchema: String? = nil) = #externalMacro(module: "AFMMacros", type: "ToolMacro")
#endif
