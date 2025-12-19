//
//  AppState.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

@Observable
@MainActor
class AppState {
    // MARK: - Composed State Managers

    let navigation: NavigationState
    let connection: ConnectionState
    let query: QueryState

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil
    ) {
        self.navigation = navigation ?? NavigationState()
        self.connection = connection ?? ConnectionState()
        self.query = query ?? QueryState()
    }

    // MARK: - Backwards Compatibility Facade
    // Computed properties that delegate to sub-states
    // TODO: Phase 2 - Gradually migrate views to access sub-states directly, then remove this facade

    // Navigation properties
    var navigationPath: NavigationPath {
        get { navigation.navigationPath }
        set { navigation.navigationPath = newValue }
    }

    var sidebarViewMode: SidebarViewMode {
        get { navigation.sidebarViewMode }
        set { navigation.sidebarViewMode = newValue }
    }

    var isShowingConnectionForm: Bool {
        get { navigation.isShowingConnectionForm }
        set { navigation.isShowingConnectionForm = newValue }
    }

    var isShowingConnectionsList: Bool {
        get { navigation.isShowingConnectionsList }
        set { navigation.isShowingConnectionsList = newValue }
    }

    var isShowingWelcomeScreen: Bool {
        get { navigation.isShowingWelcomeScreen }
        set { navigation.isShowingWelcomeScreen = newValue }
    }

    var connectionToEdit: ConnectionProfile? {
        get { navigation.connectionToEdit }
        set { navigation.connectionToEdit = newValue }
    }

    // Connection properties
    var currentConnection: ConnectionProfile? {
        get { connection.currentConnection }
        set { connection.currentConnection = newValue }
    }

    var isConnected: Bool {
        connection.isConnected
    }

    var databaseService: DatabaseService {
        connection.databaseService
    }

    var selectedDatabase: DatabaseInfo? {
        get { connection.selectedDatabase }
        set { connection.selectedDatabase = newValue }
    }

    var selectedTable: TableInfo? {
        get { connection.selectedTable }
        set { connection.selectedTable = newValue }
    }

    var databases: [DatabaseInfo] {
        get { connection.databases }
        set { connection.databases = newValue }
    }

    var tables: [TableInfo] {
        get { connection.tables }
        set { connection.tables = newValue }
    }

    var isLoadingTables: Bool {
        get { connection.isLoadingTables }
        set { connection.isLoadingTables = newValue }
    }

    // Query properties
    var queryText: String {
        get { query.queryText }
        set { query.queryText = newValue }
    }

    var queryResults: [TableRow] {
        get { query.queryResults }
        set { query.queryResults = newValue }
    }

    var queryColumnNames: [String]? {
        get { query.queryColumnNames }
        set { query.queryColumnNames = newValue }
    }

    var isExecutingQuery: Bool {
        get { query.isExecutingQuery }
        set { query.isExecutingQuery = newValue }
    }

    var queryError: String? {
        get { query.queryError }
        set { query.queryError = newValue }
    }

    var showQueryResults: Bool {
        get { query.showQueryResults }
        set { query.showQueryResults = newValue }
    }

    var queryExecutionTime: TimeInterval? {
        get { query.queryExecutionTime }
        set { query.queryExecutionTime = newValue }
    }

    var selectedRowIDs: Set<UUID> {
        get { query.selectedRowIDs }
        set { query.selectedRowIDs = newValue }
    }

    var currentPage: Int {
        get { query.currentPage }
        set { query.currentPage = newValue }
    }

    var rowsPerPage: Int {
        get { query.rowsPerPage }
        set { query.rowsPerPage = newValue }
    }

    // MARK: - Delegated Methods

    func showConnectionForm() {
        navigation.showConnectionForm()
    }

    func showConnectionsList() {
        navigation.showConnectionsList()
    }

    // Centralized query execution to prevent race conditions when rapidly switching tables
    @MainActor
    func executeTableQuery(for table: TableInfo) async {
        // Create query service (will be injected via DI container in Phase 6)
        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        // Set loading state
        query.isExecutingQuery = true
        query.queryError = nil
        query.queryExecutionTime = nil

        // Execute query
        let result = await queryService.executeTableQuery(
            for: table,
            limit: query.rowsPerPage,
            offset: 0
        )

        // Update state based on result
        if result.isSuccess {
            query.queryResults = result.rows
            query.queryColumnNames = result.columnNames.isEmpty ? nil : result.columnNames
            query.showQueryResults = true
            query.queryExecutionTime = result.executionTime
        } else if let error = result.error {
            query.queryError = error.localizedDescription
            query.queryColumnNames = nil
            query.showQueryResults = true
            query.queryExecutionTime = result.executionTime
        }

        query.isExecutingQuery = false
    }

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard connection.isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up...")

        // Cancel any pending queries
        query.cleanup()

        // Disconnect and reset connection state
        await connection.cleanupOnWindowClose()

        DebugLog.print("✅ Cleanup completed")
    }
}
