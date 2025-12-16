# PostgresGUI - A native PostgreSQL client for macOS

![Hero](screenshots/PostgresGUI-Query_Result_View-1440x900.jpg)

[![Version](https://img.shields.io/badge/version-1.0.3-blue.svg)](https://postgresgui.com)
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)


## Features

- **Connection Management**
- **SSL/TLS Support**
- **Database & Table Browsing**
- **SQL Query Editor**
- **Data Viewing & Editing**
- **Row Operations** - View rows as json, edit row, select rows and delete
- **Keyboard Shortcuts**
- **Native macOS Experience** - Built with SwiftUI for a fast, responsive, and familiar interface


## Getting Started

### Creating Your First Connection

1. Launch PostgresGUI
2. Click "New Connection" or use the quick localhost connection option
3. Enter your connection details:
   - Host (e.g., localhost or your server address)
   - Port (default: 5432)
   - Database name (default: postgres)
   - Username and password
   - Optional: Configure SSL settings
4. Click "Test Connection" to verify
5. Save your connection profile

### Running SQL Queries

1. Click the "Query" tab or button to open the query editor
2. Write your SQL query
3. Press `Cmd+Return` to execute
4. View results in the table below, including execution time and row count

### Keyboard Shortcuts

- `Cmd+R` - Refresh current view
- `Cmd+Return` - Execute SQL query
- `Space` - View selected row in JSON format
- `Delete` - Delete selected row(s)

## Building from Source

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/postgresgui.git
   cd postgresgui
   ```

2. Open in Xcode:
   ```bash
   open PostgresGUI.xcodeproj
   ```

3. Build and run:
   - Select the PostgresGUI scheme
   - Press `Cmd+R` to build and run
   - Swift Package Manager will automatically resolve dependencies

All dependencies are managed through Swift Package Manager and will be downloaded automatically on first build.

## Support

- Visit [postgresgui.com/support](https://postgresgui.com/support) for help and documentation
- Report bugs on [GitHub Issues](https://github.com/yourusername/postgresgui/issues)

## Acknowledgments

PostgresGUI is built on the shoulders of giants. Special thanks to:

- The [PostgresNIO](https://github.com/vapor/postgres-nio) team for the excellent PostgreSQL client library
- The [Swift NIO](https://github.com/apple/swift-nio) project for the networking foundation
- The [CodeEditorView](https://github.com/mchakravarty/CodeEditorView) project for syntax highlighting capabilities
