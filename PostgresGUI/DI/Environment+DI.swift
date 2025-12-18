//
//  Environment+DI.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

// MARK: - Environment Keys

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue = ServiceContainer.shared
}

private struct ViewModelFactoryKey: EnvironmentKey {
    static let defaultValue = ViewModelFactory()
}

// MARK: - Environment Values Extension

extension EnvironmentValues {
    /// Access the service container from the environment
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }

    /// Access the ViewModel factory from the environment
    var viewModelFactory: ViewModelFactory {
        get { self[ViewModelFactoryKey.self] }
        set { self[ViewModelFactoryKey.self] = newValue }
    }
}
