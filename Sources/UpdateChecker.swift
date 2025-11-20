import Foundation

struct UpdateChecker {
    static let currentVersion: String = {
        // Try to read version from VERSION file bundled with the binary
        // This file should be in the same directory as the executable or in Resources
        if let versionString = try? String(contentsOf: versionFileURL(), encoding: .utf8) {
            return versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback version if VERSION file is not found
        return "0.5.1"
    }()

    static let repo = "thillsman/XCStringsLocalizer"
    static let cacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".xcstrings-localizer-version-check")

    private static func versionFileURL() -> URL {
        // First try: VERSION file in the same directory as the executable
        if let executablePath = Bundle.main.executablePath {
            let executableURL = URL(fileURLWithPath: executablePath)
            let versionURL = executableURL.deletingLastPathComponent().appendingPathComponent("VERSION")
            if FileManager.default.fileExists(atPath: versionURL.path) {
                return versionURL
            }
        }

        // Second try: VERSION file in Resources bundle (for development)
        if let resourceURL = Bundle.main.url(forResource: "VERSION", withExtension: nil) {
            return resourceURL
        }

        // Third try: VERSION file in the root of the package (for development with swift run)
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let versionURL = currentDirectory.appendingPathComponent("VERSION")
        if FileManager.default.fileExists(atPath: versionURL.path) {
            return versionURL
        }

        // Fourth try: Go up directories to find VERSION (for development)
        var searchURL = currentDirectory
        for _ in 0..<5 {
            let versionURL = searchURL.appendingPathComponent("VERSION")
            if FileManager.default.fileExists(atPath: versionURL.path) {
                return versionURL
            }
            searchURL = searchURL.deletingLastPathComponent()
        }

        // Fallback to current directory
        return currentDirectory.appendingPathComponent("VERSION")
    }

    struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
    }

    struct VersionCache: Codable {
        let latestVersion: String
        let checkedAt: Date

        var isExpired: Bool {
            // Cache for 24 hours
            Date().timeIntervalSince(checkedAt) > 86400
        }
    }

    /// Check for updates and notify user if a newer version is available
    /// Non-blocking, prints to stderr
    static func checkForUpdatesAsync() {
        Task {
            await checkForUpdates(silent: true)
        }
    }

    /// Check for updates synchronously
    @discardableResult
    static func checkForUpdates(silent: Bool = false) async -> Bool {
        // Check cache first
        if let cached = loadCache(), !cached.isExpired {
            if !silent && compareVersions(cached.latestVersion, currentVersion) == .orderedDescending {
                printUpdateAvailable(version: cached.latestVersion)
            }
            return compareVersions(cached.latestVersion, currentVersion) == .orderedDescending
        }

        // Fetch latest release
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")

            // Save to cache
            let cache = VersionCache(latestVersion: latestVersion, checkedAt: Date())
            saveCache(cache)

            // Check if update available
            if compareVersions(latestVersion, currentVersion) == .orderedDescending {
                if !silent {
                    printUpdateAvailable(version: latestVersion)
                }
                return true
            }

            return false
        } catch {
            // Silently fail - don't interrupt user experience
            return false
        }
    }

    /// Perform self-update by downloading and installing latest version
    static func performUpdate() async throws {
        print("Checking for updates...", to: &stderrStream)

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw UpdateError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError("Failed to fetch release information")
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")

        print("Latest version: \(release.tagName)", to: &stderrStream)
        print("Current version: \(currentVersion)", to: &stderrStream)

        // Compare versions
        let comparison = compareVersions(latestVersion, currentVersion)
        if comparison == .orderedSame {
            print("\n✓ Already up to date!", to: &stderrStream)
            return
        } else if comparison == .orderedAscending {
            print("\n⚠ Current version is newer than latest release", to: &stderrStream)
            print("This might be a development version.", to: &stderrStream)
            return
        }

        print("\n🎉 New version available: \(release.tagName)", to: &stderrStream)

        // Find macOS asset
        guard let macOSAsset = release.assets.first(where: { $0.name.contains("macos.zip") }) else {
            throw UpdateError.noMacOSBinary
        }

        print("Downloading \(macOSAsset.name)...", to: &stderrStream)

        guard let downloadURL = URL(string: macOSAsset.browserDownloadUrl) else {
            throw UpdateError.networkError("Invalid download URL")
        }

        let (zipData, _) = try await URLSession.shared.data(from: downloadURL)

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Save zip file
        let zipPath = tempDir.appendingPathComponent("xcstrings-localizer.zip")
        try zipData.write(to: zipPath)

        // Extract zip
        print("Extracting...", to: &stderrStream)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipPath.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.extractionFailed
        }

        let binaryPath = tempDir.appendingPathComponent("xcstrings-localizer")
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw UpdateError.binaryNotFound
        }

        let versionFilePath = tempDir.appendingPathComponent("VERSION")
        guard FileManager.default.fileExists(atPath: versionFilePath.path) else {
            throw UpdateError.versionFileNotFound
        }

        // Get current binary location
        guard let currentBinaryPath = getCurrentBinaryPath() else {
            throw UpdateError.cannotDetermineCurrentLocation
        }

        print("Installing to \(currentBinaryPath)...", to: &stderrStream)

        // Check if we can write to the location
        let currentBinaryURL = URL(fileURLWithPath: currentBinaryPath)
        let parentDir = currentBinaryURL.deletingLastPathComponent()
        let currentVersionURL = parentDir.appendingPathComponent("VERSION")

        // Use atomic replacement: copy to temp location in same directory, then replace
        // This ensures we don't delete the old binary until the new one is successfully in place
        let tempBinaryPath = parentDir.appendingPathComponent(".\(UUID().uuidString)-xcstrings-localizer.tmp")
        let tempVersionPath = parentDir.appendingPathComponent(".\(UUID().uuidString)-VERSION.tmp")

        if FileManager.default.isWritableFile(atPath: parentDir.path) {
            // Direct atomic replacement
            // 1. Copy new binary and VERSION to temp locations
            try FileManager.default.copyItem(at: binaryPath, to: tempBinaryPath)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempBinaryPath.path)
            try FileManager.default.copyItem(at: versionFilePath, to: tempVersionPath)

            // 2. Atomically replace old binary with new one
            // replaceItemAt is atomic on the same filesystem
            _ = try FileManager.default.replaceItemAt(
                currentBinaryURL,
                withItemAt: tempBinaryPath,
                backupItemName: nil,
                options: []
            )

            // 3. Replace VERSION file (or create if it doesn't exist)
            if FileManager.default.fileExists(atPath: currentVersionURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    currentVersionURL,
                    withItemAt: tempVersionPath,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: tempVersionPath, to: currentVersionURL)
            }
        } else {
            // Need sudo - use mv which is atomic on the same filesystem
            print("\nNeed administrator permission to update...", to: &stderrStream)

            // First copy binary and VERSION to temp locations with sudo
            let copyBinaryProcess = Process()
            copyBinaryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            copyBinaryProcess.arguments = ["cp", binaryPath.path, tempBinaryPath.path]
            try copyBinaryProcess.run()
            copyBinaryProcess.waitUntilExit()

            guard copyBinaryProcess.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tempBinaryPath)
                throw UpdateError.installationFailed
            }

            let copyVersionProcess = Process()
            copyVersionProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            copyVersionProcess.arguments = ["cp", versionFilePath.path, tempVersionPath.path]
            try copyVersionProcess.run()
            copyVersionProcess.waitUntilExit()

            guard copyVersionProcess.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tempBinaryPath)
                try? FileManager.default.removeItem(at: tempVersionPath)
                throw UpdateError.installationFailed
            }

            // Set permissions on binary
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            chmodProcess.arguments = ["chmod", "755", tempBinaryPath.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()

            // Atomically move temp files to final locations (mv is atomic on same filesystem)
            let mvBinaryProcess = Process()
            mvBinaryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            mvBinaryProcess.arguments = ["mv", "-f", tempBinaryPath.path, currentBinaryPath]
            try mvBinaryProcess.run()
            mvBinaryProcess.waitUntilExit()

            guard mvBinaryProcess.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tempBinaryPath)
                try? FileManager.default.removeItem(at: tempVersionPath)
                throw UpdateError.installationFailed
            }

            let mvVersionProcess = Process()
            mvVersionProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            mvVersionProcess.arguments = ["mv", "-f", tempVersionPath.path, currentVersionURL.path]
            try mvVersionProcess.run()
            mvVersionProcess.waitUntilExit()

            guard mvVersionProcess.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tempVersionPath)
                throw UpdateError.installationFailed
            }
        }

        print("\n✓ Successfully updated to \(release.tagName)!", to: &stderrStream)
        print("\nRun 'xcstrings-localizer --version' to verify.", to: &stderrStream)
    }

    // MARK: - Helper Methods

    private static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func printUpdateAvailable(version: String) {
        print("", to: &stderrStream)
        print("╭─────────────────────────────────────────────────╮", to: &stderrStream)
        print("│  🎉 New version available: v\(version.padding(toLength: 18, withPad: " ", startingAt: 0))│", to: &stderrStream)
        print("│  Current version: v\(currentVersion.padding(toLength: 24, withPad: " ", startingAt: 0))│", to: &stderrStream)
        print("│                                                 │", to: &stderrStream)
        print("│  Update now:                                    │", to: &stderrStream)
        print("│    xcstrings-localizer update                   │", to: &stderrStream)
        print("╰─────────────────────────────────────────────────╯", to: &stderrStream)
        print("", to: &stderrStream)
    }

    private static func getCurrentBinaryPath() -> String? {
        guard let path = ProcessInfo.processInfo.arguments.first else {
            return nil
        }

        // If it's already an absolute path, return it
        if path.hasPrefix("/") {
            return path
        }

        // Otherwise, try to resolve it
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output
        } catch {
            return nil
        }
    }

    private static func loadCache() -> VersionCache? {
        guard let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }
        return try? JSONDecoder().decode(VersionCache.self, from: data)
    }

    private static func saveCache(_ cache: VersionCache) {
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? data.write(to: cacheFile)
    }

    enum UpdateError: LocalizedError {
        case networkError(String)
        case noMacOSBinary
        case extractionFailed
        case binaryNotFound
        case versionFileNotFound
        case cannotDetermineCurrentLocation
        case installationFailed

        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                return "Network error: \(message)"
            case .noMacOSBinary:
                return "No macOS binary found in release"
            case .extractionFailed:
                return "Failed to extract downloaded file"
            case .binaryNotFound:
                return "Binary not found in extracted files"
            case .versionFileNotFound:
                return "VERSION file not found in extracted files"
            case .cannotDetermineCurrentLocation:
                return "Cannot determine current binary location"
            case .installationFailed:
                return "Failed to install update"
            }
        }
    }
}
