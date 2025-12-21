//
//  PaginationView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct PaginationView: View {
    @Environment(AppState.self) private var appState
    let totalRows: Int64
    
    var totalPages: Int {
        max(1, Int(ceil(Double(totalRows) / Double(appState.query.rowsPerPage))))
    }

    var currentPage: Int {
        appState.query.currentPage
    }
    
    var body: some View {
        HStack {
            Button(action: previousPage) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage == 0)
            
            Text("Page \(currentPage + 1) of \(totalPages)")
                .frame(minWidth: 120)
            
            Button(action: nextPage) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages - 1)
            
            Spacer()
            
            Text("Rows per page:")
            Picker("Rows per page", selection: Binding(
                get: { appState.query.rowsPerPage },
                set: { appState.query.rowsPerPage = $0 }
            )) {
                Text("10").tag(10)
                Text("50").tag(50)
                Text("100").tag(100)
                Text("500").tag(500)
                Text("1000").tag(1000)
            }
            .frame(width: 100)
        }
        .padding()
    }
    
    private func previousPage() {
        if currentPage > 0 {
            appState.query.currentPage -= 1
        }
    }

    private func nextPage() {
        if currentPage < totalPages - 1 {
            appState.query.currentPage += 1
        }
    }
}
