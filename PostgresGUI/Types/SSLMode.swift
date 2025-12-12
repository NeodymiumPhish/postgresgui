//
//  SSLMode.swift
//  PostgresGUI
//
//  Created by ghazi
//

import Foundation
import NIOSSL

/// SSL mode options for PostgreSQL connections
enum SSLMode: String, Sendable {
    case disable = "disable"
    case allow = "allow"
    case prefer = "prefer"
    case require = "require"
    case verifyCA = "verify-ca"
    case verifyFull = "verify-full"

    /// Default SSL mode when not specified
    /// Using 'disable' as default for better localhost compatibility
    nonisolated static let `default` = SSLMode.disable

    /// Convert SSLMode to NIO TLSConfiguration
    /// - Returns: TLSConfiguration for NIO, or nil if SSL is disabled
    nonisolated var nioTLSConfiguration: TLSConfiguration? {
        switch self {
        case .disable:
            // No TLS
            return nil

        case .allow, .prefer:
            // Opportunistic TLS - prefer encrypted but allow unencrypted
            // PostgresNIO doesn't support automatic SSL fallback, so we disable SSL
            // for these modes to ensure connectivity (especially for localhost)
            return nil

        case .require:
            // Require TLS but don't verify certificate
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .none
            return config

        case .verifyCA:
            // Require TLS and verify CA
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .noHostnameVerification
            return config

        case .verifyFull:
            // Require TLS and verify full certificate chain including hostname
            return TLSConfiguration.makeClientConfiguration()
        }
    }
}
