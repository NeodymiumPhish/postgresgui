//
//  SSLMode.swift
//  PostgresGUI
//
//  Created by ghazi
//

import Foundation

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

    /// Convert SSLMode to abstract DatabaseTLSMode
    /// - Returns: DatabaseTLSMode for connection manager
    nonisolated var databaseTLSMode: DatabaseTLSMode {
        switch self {
        case .disable, .allow, .prefer:
            // No TLS or opportunistic TLS (PostgresNIO doesn't support fallback)
            return .disable

        case .require:
            // Require TLS but don't verify certificate
            return .require

        case .verifyCA:
            // Require TLS and verify CA
            return .verifyCA

        case .verifyFull:
            // Require TLS and verify full certificate chain including hostname
            return .verifyFull
        }
    }
}
