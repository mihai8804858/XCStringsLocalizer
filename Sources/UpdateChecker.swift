import Foundation

struct UpdateChecker {
    static let currentVersion = "0.4.0"
    static let repo = "tylerhillsman/XCStringsLocalizer"
    static let cacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".xcstrings-localizer-version-check")

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

        // Get current binary location
        guard let currentBinaryPath = getCurrentBinaryPath() else {
            throw UpdateError.cannotDetermineCurrentLocation
        }

        print("Installing to \(currentBinaryPath)...", to: &stderrStream)

        // Check if we can write to the location
        let currentBinaryURL = URL(fileURLWithPath: currentBinaryPath)
        let parentDir = currentBinaryURL.deletingLastPathComponent().path

        if FileManager.default.isWritableFile(atPath: parentDir) {
            // Direct copy
            try FileManager.default.removeItem(atPath: currentBinaryPath)
            try FileManager.default.copyItem(at: binaryPath, to: currentBinaryURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentBinaryPath)
        } else {
            // Need sudo
            print("\nNeed administrator permission to update...", to: &stderrStream)
            let sudoProcess = Process()
            sudoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            sudoProcess.arguments = ["mv", binaryPath.path, currentBinaryPath]
            try sudoProcess.run()
            sudoProcess.waitUntilExit()

            guard sudoProcess.terminationStatus == 0 else {
                throw UpdateError.installationFailed
            }

            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            chmodProcess.arguments = ["chmod", "+x", currentBinaryPath]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
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
            case .cannotDetermineCurrentLocation:
                return "Cannot determine current binary location"
            case .installationFailed:
                return "Failed to install update"
            }
        }
    }
}
