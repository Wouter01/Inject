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

extension DeclSyntaxProtocol {
    var hasViewBuilder: Bool {
        if let funcDecl = self.as(FunctionDeclSyntax.self) {
            return funcDecl.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "ViewBuilder"
            }
        } else if let varDecl = self.as(VariableDeclSyntax.self) {
            return varDecl.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "ViewBuilder"
            }
        }
        
        return false
    }
}

public struct HotReloadMacro: MemberMacro {
    
    static func conformsto(protocol: String, _ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == `protocol`
        }

        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == `protocol`
                && member.baseType.description.trimmingCharacters(in: .whitespacesAndNewlines) == "SwiftUI"
        }

        return false
    }
    
    static func isBodyProperty(_ decl: some DeclSyntaxProtocol) -> Bool {
        guard let varDecl = decl.as(VariableDeclSyntax.self) else {
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

            return conformsto(protocol: "View", someType.constraint)
        }
    }
    
    static func isBodyFunction(_ decl: some DeclSyntaxProtocol) -> Bool {
        
        guard let funcDecl = decl.as(FunctionDeclSyntax.self) else {
            return false
        }
        
        guard
            funcDecl.name.text == "body",
            let someType = funcDecl.signature.returnClause?.type.as(SomeOrAnyTypeSyntax.self),
            someType.someOrAnySpecifier.tokenKind == .keyword(.some)
        else {
            return false
        }
      
        return conformsto(protocol: "View", someType.constraint)
    }
    
    static func declConformsTo(protocol name: String, _ decl: StructDeclSyntax) -> Bool {
        decl
            .inheritanceClause?
            .inheritedTypes
            .lazy
            .map(\.type)
            .contains { conformsto(protocol: name, $0) } == true
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
        
        let memberDecls = declaration.memberBlock.members.lazy.map(\.decl)
        
        if declConformsTo(protocol: "View", declaration) {
            // Prevents applying macro before a view body is declared
            // This fixes two issues:
            //  - The macro overriding the Body typealias, which causes autocomplete to fill in `var body: AnyView`
            //  - The macro providing a valid `body` implementation, but no existing declaration is present.
            //      This will compile, but will cause an infinite loop.
            guard memberDecls.contains(where: isBodyProperty) else {
                context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("\(declaration.name) must have a View body")))
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
            
        } else if declConformsTo(protocol: "ViewModifier", declaration) {
            // Prevents applying macro before a view body is declared
            // This fixes two issues:
            //  - The macro overriding the Body typealias, which causes autocomplete to fill in `var body: AnyView`
            //  - The macro providing a valid `body` implementation, but no existing declaration is present.
            //      This will compile, but will cause an infinite loop.
            guard memberDecls.contains(where: isBodyFunction) else {
                context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("\(declaration.name) must have a ViewModifier body function")))
                return []
            }
            
            var accessControl = declaration.modifiers.first(where: { $0.name.tokenKind.isVisibilityKeyword })?.name.trimmed
            accessControl?.trailingTrivia = .space
            
            return [
                """
                #if DEBUG
                
                @ObserveInjection private var __observeInjection
                
                \(accessControl)typealias Body = AnyView
                
                @_implements(ViewModifier, body(content:))
                @_disfavoredOverload
                @ViewBuilder
                \(accessControl)func __body(content: Content) -> AnyView {
                    AnyView(body(content: content))
                }
                #endif
                """
            ]
        } else {
            // Not stricly necessary, mostly to prevent misuse of macro
            // Will cause false positive when the View conformance is declared in an extension.
            context.diagnose(.init(node: declaration, message: MacroExpansionErrorMessage("\(declaration.name) must conform to the View or ViewModifier protocol")))
            return []
        }
    }
}

extension HotReloadMacro: MemberAttributeMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        guard
            !member.hasViewBuilder,
            let declaration = declaration.as(StructDeclSyntax.self)
        else {
            return []
        }
        
        if declConformsTo(protocol: "View", declaration) && isBodyProperty(member) {
            return ["@ViewBuilder"]
        }
        
        if declConformsTo(protocol: "ViewModifier", declaration) && isBodyFunction(member) {
            return ["@ViewBuilder"]
        }
        
        return []
    }
}

@main
struct MyMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        HotReloadMacro.self,
    ]
}

#endif
