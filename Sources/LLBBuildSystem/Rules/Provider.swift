// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import llbuild2
import Foundation

public protocol LLBProvider: LLBPolymorphicCodable {}

/// Convenience implementation for LLBProviders that conform to Codable
extension LLBProvider where Self: Encodable {
    public func encode() throws -> LLBByteBuffer {
        let data = try JSONEncoder().encode(self)
        return LLBByteBuffer.withBytes(ArraySlice<UInt8>(data))
    }
}

/// Convenience implementation for LLBProviders that conform to Codable
extension LLBProvider where Self: Decodable {
    public init(from bytes: LLBByteBuffer) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(bytes.readableBytesView))
    }
}

public enum LLBProviderMapError: Error {
    /// Thrown when there are multiple providers of the same type being added to a ProviderMap.
    case multipleProviders(String)
    
    /// Thrown when an unknown
    case providerTypeNotFound(String)
}

public extension LLBProviderMap {
    init(providers: [LLBProvider]) throws {
        // Sort providers to create a deterministic output.
        var validProviders = [LLBAnyCodable]()
        try providers.sorted {
            type(of: $0).polymorphicIdentifier < type(of: $1).polymorphicIdentifier
        }.forEach { provider in
            if let lastCodable = validProviders.last,
                  lastCodable.typeIdentifier == type(of: provider).polymorphicIdentifier {
                throw LLBProviderMapError.multipleProviders(String(describing: type(of: provider).polymorphicIdentifier))
            }
            validProviders.append(try LLBAnyCodable(from: provider))
        }
        self.providers = validProviders
    }
    
    var count: Int {
        return providers.count
    }
}

/// Convenience implementation of LLBProviderMap as Codable for use by clients of llbuild2.
extension LLBProviderMap: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(serializedData: container.decode(Data.self))
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.serializedData())
    }
}

extension LLBProviderMap {
    /// Returns the provider contained in the map for the given provider type, or throws if none is found.
    public func get<P: LLBProvider>(_ type: P.Type = P.self) throws -> P {
        for anyProvider in providers {
            if anyProvider.typeIdentifier == P.polymorphicIdentifier {
                let byteBuffer = LLBByteBuffer.withBytes(ArraySlice<UInt8>(anyProvider.serializedCodable))
                return try P.init(from: byteBuffer)
            }
        }
        
        throw LLBProviderMapError.providerTypeNotFound(P.polymorphicIdentifier)
    }
}