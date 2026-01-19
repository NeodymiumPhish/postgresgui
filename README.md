# PostgresGUI - A native PostgreSQL client for macOS

![PostgresGUI screenshot in dark mode](https://github.com/PostgresGUI/website/blob/main/public/screenshots2/PostgresGUI%20-%20Dark%20mode.png?raw=true)

[![Version](https://img.shields.io/badge/version-1.0.7-blue.svg)](https://postgresgui.com)
  [![Platform](https://img.shields.io/badge/platform-macOS%2026-lightgrey.svg)](https://www.apple.com/macos)

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
2. Click "New Connection"
3. Enter your connection details:
   - Host (e.g., localhost or your server address)
   - Port (default: 5432)
   - Database name (default: postgres)
   - Username and password
4. Click "Test Connection" to verify
5. Save your connection profile

### Keyboard Shortcuts

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

### About Contributing

You might encounter "Automatic signing failed" issues when building from source. This happens because the project's code signing settings are tied to the maintainer's Apple Developer Team ID and bundle identifier.

**To fix this, please try the following:**

1. Select the **PostgresGUI** target in Xcode
2. Go to the **Signing & Capabilities** tab
3. Change the **Bundle Identifier** to something unique (e.g., `com.yourname.PostgresGUI-dev`)
4. Set **Team** to your Personal Team or your own Apple Developer account

**Why the signing configuration is hardcoded:**

The signing settings are intentionally kept hardcoded in the repository. The app uses Keychain to securely store database passwords, and Keychain access is tied to the app's code signature. Without consistent code signing (same Team ID and bundle identifier), macOS treats each build as a different app and prompts the user for Keychain permission every time the app accesses stored passwords — which is disruptive.

If you'd like to contribute, feel free to submit a pull request. I can test it locally on my machine and provide screenshots to confirm everything works correctly. (Fikri Ghazi Jan 18, 2026)

## Support

- Visit [postgresgui.com/support](https://postgresgui.com/support) for help and documentation
- Report bugs on [GitHub Issues](https://github.com/yourusername/postgresgui/issues)

## Acknowledgments

PostgresGUI is built on the shoulders of giants. Special thanks to:

- The [PostgresNIO](https://github.com/vapor/postgres-nio) team for the excellent PostgreSQL client library
- The [Swift NIO](https://github.com/apple/swift-nio) project for the networking foundation
