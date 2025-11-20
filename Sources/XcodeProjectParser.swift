import Foundation

/// Utility for parsing Xcode project files to extract configuration
struct XcodeProjectParser {
    /// Find the first .xcodeproj in the current directory or parent directories
    static func findXcodeProject(startingFrom path: String = FileManager.default.currentDirectoryPath) -> String? {
        var currentPath = path

        // Search up to 3 levels up from the current directory
        for _ in 0..<3 {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: currentPath)
            if let xcodeproj = contents?.first(where: { $0.hasSuffix(".xcodeproj") }) {
                return (currentPath as NSString).appendingPathComponent(xcodeproj)
            }

            // Move up one directory
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath == currentPath {
                break // We've reached the root
            }
            currentPath = parentPath
        }

        return nil
    }

    /// Extract knownRegions from an Xcode project's project.pbxproj file
    static func extractKnownRegions(from projectPath: String) -> [String]? {
        let pbxprojPath = (projectPath as NSString).appendingPathComponent("project.pbxproj")

        guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return nil
        }

        // Parse knownRegions using regex
        // Looking for pattern like:
        // knownRegions = (
        //     en,
        //     Base,
        //     fr,
        // );

        let pattern = #"knownRegions\s*=\s*\(\s*([^)]+)\s*\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let regionsRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        let regionsString = String(content[regionsRange])

        // Extract individual language codes
        var languages = regionsString
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty && $0 != "Base" }

        // Remove "en" if it exists (it's typically the source language)
        languages = languages.filter { $0 != "en" }

        return languages.isEmpty ? nil : languages
    }

    /// Get target languages from the Xcode project, if available
    static func getProjectLanguages() -> [String]? {
        guard let projectPath = findXcodeProject() else {
            return nil
        }

        return extractKnownRegions(from: projectPath)
    }

    /// Find all .xcstrings files in the current directory and subdirectories
    static func findXCStringsFiles(in directory: String = FileManager.default.currentDirectoryPath) -> [String] {
        var xcstringsFiles: [String] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            if fileURL.pathExtension == "xcstrings" {
                xcstringsFiles.append(fileURL.path)
            }
        }

        return xcstringsFiles.sorted()
    }
}
