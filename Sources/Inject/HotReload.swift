//
//  HotReload.swift
//  Inject
//
//  Created by Wouter Hennen on 23/12/2025.
//

#if !os(watchOS)
#if HotReloadMacro

@attached(member, names: named(__observeInjection), named(Body), named(__body))
public macro HotReload() = #externalMacro(module: "HotReloadMacro", type: "HotReloadMacro")

#endif
#endif
