//
//  HotReloadMacro.swift
//  Inject
//
//  Created by Wouter Hennen on 23/12/2025.
//

#if HotReloadMacro

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

extension TokenKind {
    var isVisibilityKeyword: Bool {
        switch self {
        case .keyword(.public),
             .keyword(.private),
             .keyword(.fileprivate),
             .keyword(.internal),
             .keyword(.package),
             .keyword(.open):
            return true
        default:
            return false
        }
    }
}

public struct HotReloadMacro: MemberMacro {
    
    static func isViewType(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "View"
        }

        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == "View"
                && member.baseType.description.trimmingCharacters(in: .whitespacesAndNewlines) == "SwiftUI"
        }

        return false
    }
    
    static func hasBodyProperty(_ structDecl: StructDeclSyntax) -> Bool {
        structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                return false
            }

            return varDecl.bindings.contains { binding in
                guard
                    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                    identifier.identifier.text == "body",
                    let typeAnnotation = binding.typeAnnotation,
                    let someType = typeAnnotation.type.as(SomeOrAnyTypeSyntax.self),
                    someType.someOrAnySpecifier.tokenKind == .keyword(.some)
                else {
                    return false
                }

                return isViewType(someType.constraint)
            }
        }
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        // Not stricly necessary, mostly to prevent misuse of macro
        // A View can technically be an enum, but we cannot support that case as we cannot add the `ObserveInjection` property wrapper.
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("HotReload macro must be attached to a struct")))
            return []
        }
        
        // Not stricly necessary, mostly to prevent misuse of macro
        // Will cause false positive when the View conformance is declared in an extension.
        guard declaration.inheritanceClause?.inheritedTypes.lazy.map(\.type).contains(where: isViewType) == true else {
            context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("\(declaration.name) must conform to the View protocol")))
            return []
        }
        
        // Prevents applying macro before a view body is declared
        // This fixes two issues:
        //  - The macro overriding the Body typealias, which causes autocomplete to fill in `var body: AnyView`
        //  - The macro providing a valid `body` implementation, but no existing declaration is present.
        //      This will compile, but will cause an infinite loop.
        guard hasBodyProperty(declaration) else {
            context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("\(declaration.name) must have a view body")))
            return []
        }
        
        var accessControl = declaration.modifiers.first(where: { $0.name.tokenKind.isVisibilityKeyword })?.name.trimmed
        accessControl?.trailingTrivia = .space
        
        return [
            """
            #if DEBUG
            
            @ObserveInjection private var __observeInjection
            
            \(accessControl)typealias Body = AnyView
            
            @_implements(View, body)
            @_disfavoredOverload
            @ViewBuilder
            \(accessControl)var __body: AnyView {
                AnyView(body)
            }
            #endif
            """
        ]
    }
}

@main
struct MyMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        HotReloadMacro.self,
    ]
}

#endif
