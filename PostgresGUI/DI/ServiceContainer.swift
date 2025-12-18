//
//  ServiceContainer.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Central dependency injection container
/// Manages all service instances and their dependencies
@MainActor
class ServiceContainer {
    static let shared = ServiceContainer()

    // MARK: - State Managers

    private(set) lazy var navigationState = NavigationState()
    private(set) lazy var connectionState = ConnectionState()
    private(set) lazy var queryState = QueryState()

    private(set) lazy var appState = AppState(
        navigation: navigationState,
        connection: connectionState,
        query: queryState
    )

    // MARK: - Core Services

    private var _keychainService: KeychainServiceProtocol?
    var keychainService: KeychainServiceProtocol {
        if _keychainService == nil {
            _keychainService = KeychainServiceImpl()
        }
        return _keychainService!
    }

    private var _connectionService: ConnectionServiceProtocol?
    var connectionService: ConnectionServiceProtocol {
        if _connectionService == nil {
            _connectionService = ConnectionService(
                appState: appState,
                keychainService: keychainService
            )
        }
        return _connectionService!
    }

    private var _queryService: QueryServiceProtocol?
    var queryService: QueryServiceProtocol {
        if _queryService == nil {
            _queryService = QueryService(
                databaseService: appState.databaseService,
                queryState: queryState
            )
        }
        return _queryService!
    }

    private var _rowOperationsService: RowOperationsServiceProtocol?
    var rowOperationsService: RowOperationsServiceProtocol {
        if _rowOperationsService == nil {
            _rowOperationsService = RowOperationsService()
        }
        return _rowOperationsService!
    }

    // MARK: - Testing Support

    /// Reset all services (for testing)
    func reset() {
        _keychainService = nil
        _connectionService = nil
        _queryService = nil
        _rowOperationsService = nil
    }

    /// Inject a custom keychain service (for testing)
    func inject(keychainService: KeychainServiceProtocol) {
        _keychainService = keychainService
    }

    /// Inject a custom connection service (for testing)
    func inject(connectionService: ConnectionServiceProtocol) {
        _connectionService = connectionService
    }

    /// Inject a custom query service (for testing)
    func inject(queryService: QueryServiceProtocol) {
        _queryService = queryService
    }

    /// Inject a custom row operations service (for testing)
    func inject(rowOperationsService: RowOperationsServiceProtocol) {
        _rowOperationsService = rowOperationsService
    }

    private init() {
        // Private initializer for singleton
    }
}
