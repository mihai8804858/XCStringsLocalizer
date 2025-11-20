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

    /// Find the localized-extras directory if it exists
    static func findLocalizedExtrasDirectory(in directory: String = FileManager.default.currentDirectoryPath) -> String? {
        let localizedExtrasPath = (directory as NSString).appendingPathComponent("localized-extras")
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(atPath: localizedExtrasPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return localizedExtrasPath
        }

        return nil
    }

    /// Find source files in localized-extras that don't have language suffixes
    /// Returns array of file paths that need translation
    static func findLocalizedExtrasSourceFiles(in directory: String) -> [String] {
        var sourceFiles: [String] = []
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }

        for filename in contents {
            let filePath = (directory as NSString).appendingPathComponent(filename)

            // Skip directories
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }

            // Skip hidden files
            if filename.hasPrefix(".") {
                continue
            }

            // Check if filename has a language suffix by testing if the suffix is a valid language code
            let nameWithoutExtension = (filename as NSString).deletingPathExtension
            let components = nameWithoutExtension.components(separatedBy: ".")

            var hasLanguageSuffix = false
            if components.count >= 2 {
                // Get the last component (potential language code)
                let possibleLanguageCode = components.last!

                // Use Locale to check if it's a valid language code
                let locale = Locale(identifier: "en")
                if locale.localizedString(forLanguageCode: possibleLanguageCode) != possibleLanguageCode {
                    // If the localized string is different from the code, it's a valid language
                    hasLanguageSuffix = true
                }
            }

            // If no language suffix, it's a source file
            if !hasLanguageSuffix {
                sourceFiles.append(filePath)
            }
        }

        return sourceFiles.sorted()
    }

    /// Generate localized file path for a source file
    /// Example: /path/appstore.md + "fr" -> /path/appstore.fr.md
    static func localizedFilePath(for sourcePath: String, language: String) -> String {
        let directory = (sourcePath as NSString).deletingLastPathComponent
        let filename = (sourcePath as NSString).lastPathComponent
        let nameWithoutExtension = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension

        let localizedFilename: String
        if !fileExtension.isEmpty {
            localizedFilename = "\(nameWithoutExtension).\(language).\(fileExtension)"
        } else {
            localizedFilename = "\(nameWithoutExtension).\(language)"
        }

        return (directory as NSString).appendingPathComponent(localizedFilename)
    }
}
