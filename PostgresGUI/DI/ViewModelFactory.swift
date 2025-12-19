//
//  ViewModelFactory.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Factory for creating ViewModels with proper dependency injection
@MainActor
class ViewModelFactory {
    private let services: ServiceContainer

    init(services: ServiceContainer) {
        self.services = services
    }

    convenience init() {
        self.init(services: .shared)
    }

    // MARK: - ViewModel Creation

    func makeConnectionFormViewModel(connectionToEdit: ConnectionProfile?) -> ConnectionFormViewModel {
        ConnectionFormViewModel(
            appState: services.appState,
            connectionService: services.connectionService,
            keychainService: services.keychainService,
            connectionToEdit: connectionToEdit
        )
    }

    func makeConnectionsListViewModel() -> ConnectionsListViewModel {
        ConnectionsListViewModel(
            appState: services.appState,
            connectionService: services.connectionService,
            keychainService: services.keychainService
        )
    }

    func makeSidebarViewModel() -> SidebarViewModel {
        SidebarViewModel(
            appState: services.appState,
            connectionService: services.connectionService
        )
    }

    func makeQueryEditorViewModel() -> QueryEditorViewModel {
        QueryEditorViewModel(
            appState: services.appState,
            queryService: services.queryService
        )
    }

    func makeDetailContentViewModel() -> DetailContentViewModel {
        DetailContentViewModel(
            appState: services.appState,
            rowOperations: services.rowOperationsService,
            queryService: services.queryService
        )
    }
}
