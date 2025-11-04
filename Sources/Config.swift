import Foundation

// MARK: - Configuration

/// Configuration manager for API keys and settings
struct Config {
    /// Load API key from environment or .env file
    static func loadAPIKey(from commandLine: String?) -> String? {
        // 1. Check command line argument
        if let key = commandLine, !key.isEmpty {
            return key
        }

        // 2. Check environment variable
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }

        // 3. Try to load from .env file
        if let env = loadFromDotEnv(), let key = env["OPENAI_API_KEY"] {
            return key
        }

        return nil
    }

    /// Load app description from environment or .env file
    static func loadAppDescription() -> String? {
        // 1. Check environment variable
        if let desc = ProcessInfo.processInfo.environment["APP_DESCRIPTION"], !desc.isEmpty {
            return desc
        }

        // 2. Try to load from .env file
        if let env = loadFromDotEnv(), let desc = env["APP_DESCRIPTION"] {
            return desc
        }

        return nil
    }

    /// Load .env file from current directory or script directory
    private static func loadFromDotEnv() -> [String: String]? {
        let fileManager = FileManager.default

        // Possible .env file locations
        let currentDir = fileManager.currentDirectoryPath
        let possiblePaths = [
            "\(currentDir)/.env",
            "\(currentDir)/../.env",
        ]

        for path in possiblePaths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                let env = parseEnvFile(contents)
                if !env.isEmpty {
                    return env
                }
            }
        }

        return nil
    }

    /// Parse .env file contents
    private static func parseEnvFile(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse KEY=VALUE
            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equalIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                // Remove quotes if present
                if (value.hasPrefix("'") && value.hasSuffix("'")) ||
                   (value.hasPrefix("\"") && value.hasSuffix("\"")) {
                    value = String(value.dropFirst().dropLast())
                }

                if !key.isEmpty && !value.isEmpty {
                    result[key] = value
                }
            }
        }

        return result
    }
}
