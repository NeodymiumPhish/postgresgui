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
    nonisolated static let `default` = SSLMode.prefer
}
