import Foundation

// MARK: - XCStrings Localizer

/// Main class for localizing .xcstrings files
class XCStringsLocalizer {
    private let client: OpenAIClient
    private var translationCache: [CacheKey: String] = [:]
    private var stats = TranslationStats()

    // Batch size for translation requests (tune based on model token limits)
    private let batchSize = 15

    struct CacheKey: Hashable {
        let text: String
        let targetLanguage: String
        let context: String?
    }

    init(apiKey: String, model: String = Constants.defaultModel, appDescription: String? = nil) {
        self.client = OpenAIClient(apiKey: apiKey, model: model, appDescription: appDescription)
    }

    /// Localize an .xcstrings file
    func localize(
        inputPath: String,
        outputPath: String? = nil,
        keys: [String]? = nil,
        force: Bool = false,
        dryRun: Bool = false,
        languages: [String]? = nil
    ) async throws -> TranslationStats {
        stats.reset()

        // Load the file
        print("Loading: \(inputPath)", to: &stderrStream)
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let decoder = JSONDecoder()
        var xcstrings = try decoder.decode(XCStringsFile.self, from: data)

        let sourceLanguage = xcstrings.sourceLanguage
        let allLanguages = getAllLanguages(from: xcstrings)
        var targetLanguages = allLanguages.subtracting([sourceLanguage])

        // Filter languages if specified
        if let languages {
            targetLanguages = targetLanguages.intersection(Set(languages))
            if targetLanguages.isEmpty {
                print("Error: None of the specified languages found in file", to: &stderrStream)
                return stats
            }
        }

        print("Source language: \(sourceLanguage)", to: &stderrStream)
        print("Target languages: \(targetLanguages.sorted().joined(separator: ", "))", to: &stderrStream)

        // Filter keys if specified
        var stringsToProcess = xcstrings.strings
        if let keys = keys {
            stringsToProcess = stringsToProcess.filter { keys.contains($0.key) }
            print("Translating specific keys: \(stringsToProcess.count)", to: &stderrStream)
        } else {
            print("Total keys in file: \(stringsToProcess.count)", to: &stderrStream)
        }

        stats.totalKeys = stringsToProcess.count

        // Process each string
        print("\nTranslating...\n", to: &stderrStream)

        // Group strings by target language for batch processing
        for language in targetLanguages {
            // Collect all strings that need translation for this language
            var toTranslate: [(key: String, variation: LocalizationVariation?, sourceText: String, comment: String?, entry: StringEntry)] = []

            for (key, entry) in stringsToProcess {
                // Check if we should translate this key
                if !shouldTranslateKey(entry: entry, force: force) {
                    stats.skippedShouldNotTranslate += 1
                    continue
                }

                let currentLocalization = entry.localizations?[language]
                if !needsTranslation(
                    language: language,
                    localization: currentLocalization,
                    sourceLanguage: sourceLanguage,
                    force: force
                ) {
                    stats.skippedAlreadyTranslated += 1
                    continue
                }

                for text in getSourceTexts(key: key, language: sourceLanguage, localizations: entry.localizations) {
                    toTranslate.append((
                        key: key,
                        variation: text.variation,
                        sourceText: text.value,
                        comment: entry.comment,
                        entry: entry
                    ))
                }
            }

            if toTranslate.isEmpty {
                continue
            }

            print("Translating \(toTranslate.count) strings to \(language)...", to: &stderrStream)

            // Process in batches
            let batches = toTranslate.chunked(into: batchSize)

            for (batchIndex, batch) in batches.enumerated() {
                let batchNumber = batchIndex + 1
                let totalBatches = batches.count
                print("  Batch \(batchNumber)/\(totalBatches) (\(batch.count) strings)", to: &stderrStream)

                if !dryRun {
                    do {
                        // Prepare batch input
                        let batchInput = batch.map {
                            if let variation = $0.variation {
                                (key: $0.key.appending("_\(variation)"), variation: $0.variation, text: $0.sourceText, context: $0.comment)
                            } else {
                                (key: $0.key, variation: $0.variation, text: $0.sourceText, context: $0.comment)
                            }
                        }

                        // Translate the batch
                        let translations = try await client.translateBatch(
                            strings: batchInput,
                            targetLanguage: language
                        )

                        // Apply translations
                        for item in batch {
                            let key = if let variation = item.variation {
                                item.key.appending("_\(variation)")
                            } else {
                                item.key
                            }
                            if let translated = translations[key] {
                                var entry = xcstrings.strings[item.key] ?? item.entry
                                if entry.localizations == nil { entry.localizations = [:] }
                                if let variation = item.variation {
                                    let unit = LocalizationVariationStringUnit(stringUnit: StringUnit(
                                        state: .translated,
                                        value: translated
                                    ))
                                    switch variation.type {
                                    case .plural:
                                        if entry.localizations?[language] == nil {
                                            entry.localizations?[language] = Localization(variations: .init(plural: [:]))
                                        }
                                        entry.localizations?[language]?.variations?.plural?[variation.variation] = unit
                                    case .device:
                                        if entry.localizations?[language] == nil {
                                            entry.localizations?[language] = Localization(variations: .init(device: [:]))
                                        }
                                        entry.localizations?[language]?.variations?.device?[variation.variation] = unit
                                    }
                                } else {
                                    entry.localizations?[language] = Localization(
                                        stringUnit: StringUnit(state: .translated, value: translated),
                                        variations: nil
                                    )
                                }
                                xcstrings.strings[item.key] = entry
                                stats.translated += 1
                            } else {
                                print("    ✗ Missing translation for: \(item.key)", to: &stderrStream)
                                stats.errors += 1
                            }
                        }
                    } catch {
                        print("    ✗ Batch error: \(error.localizedDescription)", to: &stderrStream)
                        stats.errors += batch.count
                    }
                } else {
                    stats.translated += batch.count
                }
            }
        }

        // Save the file if not dry run
        if !dryRun {
            let outputPath = outputPath ?? inputPath
            print("\nSaving to: \(outputPath)", to: &stderrStream)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let outputData = try encoder.encode(xcstrings)
            try outputData.write(to: URL(fileURLWithPath: outputPath))
        } else {
            print("\nDry run - no changes saved", to: &stderrStream)
        }

        // Display statistics
        print(stats.summary(), to: &stderrStream)

        return stats
    }

    /// Analyze existing translations and suggest improvements
    func suggestImprovements(
        inputPath: String,
        outputPath: String? = nil,
        keys: [String]? = nil,
        languages: [String]? = nil
    ) async throws {
        // Load the file
        print("Loading: \(inputPath)", to: &stderrStream)
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let decoder = JSONDecoder()
        var xcstrings = try decoder.decode(XCStringsFile.self, from: data)

        let sourceLanguage = xcstrings.sourceLanguage
        let allLanguages = getAllLanguages(from: xcstrings)
        var targetLanguages = allLanguages.subtracting([sourceLanguage])

        // Filter languages if specified
        if let languages = languages {
            targetLanguages = targetLanguages.intersection(Set(languages))
            if targetLanguages.isEmpty {
                print("Error: None of the specified languages found in file", to: &stderrStream)
                return
            }
        }

        print("Source language: \(sourceLanguage)", to: &stderrStream)
        if languages != nil {
            print("Analyzing languages: \(targetLanguages.sorted().joined(separator: ", "))", to: &stderrStream)
        } else {
            print("Target languages: \(targetLanguages.sorted().joined(separator: ", "))", to: &stderrStream)
        }

        // Filter keys if specified
        var stringsToProcess = xcstrings.strings
        if let keys = keys {
            stringsToProcess = stringsToProcess.filter { keys.contains($0.key) }
            print("Analyzing specific keys: \(stringsToProcess.count)", to: &stderrStream)
        } else {
            print("Total keys in file: \(stringsToProcess.count)", to: &stderrStream)
        }

        print("\nAnalyzing translations...\n", to: &stderrStream)

        var allSuggestions: [TranslationSuggestion] = []

        // Process each target language
        for language in targetLanguages.sorted() {
            // Collect all translated strings for this language
            var toAnalyze: [(key: String, variation: LocalizationVariation?, original: String, translation: String, context: String?)] = []

            for (key, entry) in stringsToProcess {
                for text in getSourceTexts(key: key, language: sourceLanguage, localizations: entry.localizations) {
                    toAnalyze.append((
                        key: key,
                        variation: text.variation,
                        original: text.value,
                        translation: text.value,
                        context: entry.comment
                    ))
                }
            }

            if toAnalyze.isEmpty {
                continue
            }

            print("Analyzing \(toAnalyze.count) translations in \(language)...", to: &stderrStream)

            // Process in batches
            let batches = toAnalyze.chunked(into: batchSize)

            for (batchIndex, batch) in batches.enumerated() {
                let batchNumber = batchIndex + 1
                let totalBatches = batches.count
                print("  Batch \(batchNumber)/\(totalBatches) (\(batch.count) strings)", to: &stderrStream)

                do {
                    let suggestions = try await client.analyzeBatch(
                        translations: batch,
                        targetLanguage: language
                    )
                    allSuggestions.append(contentsOf: suggestions)
                    if !suggestions.isEmpty {
                        print("    Found \(suggestions.count) high-confidence suggestion(s)", to: &stderrStream)
                    }
                } catch {
                    print("    ✗ Batch error: \(error.localizedDescription)", to: &stderrStream)
                }
            }
        }

        // Present suggestions interactively
        if allSuggestions.isEmpty {
            print("\n✓ No improvement suggestions found!", to: &stderrStream)
            print("All translations look good.", to: &stderrStream)
            return
        }

        print("\n┌────────────────────────────────────────────────────────────┐", to: &stderrStream)
        print("│ Found \(allSuggestions.count) suggestion(s) for improvement", to: &stderrStream)
        print("└────────────────────────────────────────────────────────────┘\n", to: &stderrStream)

        var acceptedCount = 0
        var rejectedCount = 0

        for (index, suggestion) in allSuggestions.enumerated() {
            let languageName = client.languageName(for: suggestion.language)

            print("[\(index + 1)/\(allSuggestions.count)] Key: \(suggestion.key)", to: &stderrStream)
            print("Language: \(languageName) (Confidence: \(suggestion.confidence)/5)", to: &stderrStream)
            print("", to: &stderrStream)
            print("Current:   \(suggestion.currentTranslation)", to: &stderrStream)
            print("Suggested: \(suggestion.suggestedTranslation)", to: &stderrStream)
            print("", to: &stderrStream)
            print("Reason: \(suggestion.reasoning)", to: &stderrStream)
            print("", to: &stderrStream)

            // Interactive prompt
            print("Accept this suggestion? [y/N/q] ", to: &stderrStream)

            if let response = readLine()?.lowercased() {
                if response == "q" || response == "quit" {
                    print("\nStopped by user.", to: &stderrStream)
                    break
                } else if response == "y" || response == "yes" {
                    // Apply the suggestion
                    if var entry = xcstrings.strings[suggestion.key] {
                        if entry.localizations == nil {
                            entry.localizations = [:]
                        }
                        if let variation = suggestion.variation {
                            let unit = LocalizationVariationStringUnit(stringUnit: StringUnit(
                                state: .translated,
                                value: suggestion.suggestedTranslation
                            ))
                            switch variation.type {
                            case .plural:
                                entry.localizations?[suggestion.language]?.variations?.plural?[variation.variation] = unit
                            case .device:
                                entry.localizations?[suggestion.language]?.variations?.device?[variation.variation] = unit
                            }
                        } else {
                            entry.localizations?[suggestion.language] = Localization(
                                stringUnit: StringUnit(state: .translated, value: suggestion.suggestedTranslation),
                                variations: nil
                            )
                        }
                        xcstrings.strings[suggestion.key] = entry
                        acceptedCount += 1
                        print("✓ Applied\n", to: &stderrStream)
                    }
                } else {
                    rejectedCount += 1
                    print("✗ Skipped\n", to: &stderrStream)
                }
            } else {
                rejectedCount += 1
                print("✗ Skipped\n", to: &stderrStream)
            }
        }

        // Save changes if any were accepted
        if acceptedCount > 0 {
            let outputPath = outputPath ?? inputPath
            print("Saving changes to: \(outputPath)", to: &stderrStream)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let outputData = try encoder.encode(xcstrings)
            try outputData.write(to: URL(fileURLWithPath: outputPath))

            print("\n✓ Successfully applied \(acceptedCount) suggestion(s)!", to: &stderrStream)
        } else {
            print("\nNo changes made.", to: &stderrStream)
        }

        if rejectedCount > 0 {
            print("Rejected \(rejectedCount) suggestion(s).", to: &stderrStream)
        }
    }

    // MARK: - Helper Methods

    private func getAllLanguages(from xcstrings: XCStringsFile) -> Set<String> {
        var languages = Set<String>()

        // First, try to get languages from the Xcode project's knownRegions
        if let projectLanguages = XcodeProjectParser.getProjectLanguages() {
            print("Found Xcode project with knownRegions: \(projectLanguages.joined(separator: ", "))", to: &stderrStream)
            languages = Set(projectLanguages)
        }

        // If no project found, fall back to languages in the catalog
        if languages.isEmpty {
            print("No Xcode project found, using languages from catalog", to: &stderrStream)
            for entry in xcstrings.strings.values {
                if let localizations = entry.localizations {
                    languages.formUnion(localizations.keys)
                }
            }
        }

        return languages
    }

    private func getSourceTexts(
        key: String,
        language: String,
        localizations: [String: Localization]?
    ) -> [(value: String, variation: LocalizationVariation?)] {
        guard let localization = localizations?[language] else { return [] }

        var texts: [(value: String, variation: LocalizationVariation?)] = []

        // Add default source
        if let unit = localization.stringUnit, !unit.value.isEmpty {
            texts.append((value: unit.value, variation: nil))
        }

        // Add plural sources
        if let plural = localization.variations?.plural {
            for (variation, unit) in plural where !unit.stringUnit.value.isEmpty {
                texts.append((
                    value: unit.stringUnit.value,
                    variation: LocalizationVariation(type: .plural, variation: variation)
                ))
            }
        }

        // Add device sources
        if let device = localization.variations?.device {
            for (variation, unit) in device where !unit.stringUnit.value.isEmpty {
                texts.append((
                    value: unit.stringUnit.value,
                    variation: LocalizationVariation(type: .device, variation: variation)
                ))
            }
        }

        return texts
    }

    private func shouldTranslateKey(entry: StringEntry, force: Bool) -> Bool {
        if !force, let shouldTranslate = entry.shouldTranslate, !shouldTranslate {
            return false
        }
        return true
    }

    private func needsTranslation(
        language: String,
        localization: Localization?,
        sourceLanguage: String,
        force: Bool
    ) -> Bool {
        // Skip source language
        if language == sourceLanguage {
            return false
        }

        // If no localization exists, we need to translate
        guard let localization else {
            return true
        }

        let stringUnits = [
            [localization.stringUnit].compactMap { $0 },
            localization.variations?.plural?.values.map(\.stringUnit),
            localization.variations?.device?.values.map(\.stringUnit)
        ].compactMap { $0 }.flatMap { $0 }

        if stringUnits.isEmpty { return true }

        // If force is enabled, always translate
        if force {
            return true
        }

        // Translate if state is "new" or value is empty
        return stringUnits.contains(where: \.state.needsTranslation) || stringUnits.contains(where: \.value.isEmpty)
    }

    private func translateText(
        text: String,
        targetLanguage: String,
        context: String?
    ) async throws -> String {
        // Check cache first
        let cacheKey = CacheKey(text: text, targetLanguage: targetLanguage, context: context)
        if let cached = translationCache[cacheKey] {
            return cached
        }

        // Perform translation
        let translated = try await client.translate(
            text: text,
            targetLanguage: targetLanguage,
            context: context
        )

        // Cache the result
        translationCache[cacheKey] = translated

        return translated
    }
}

// MARK: - Stderr Stream

var stderrStream = FileHandleOutputStream(fileHandle: FileHandle.standardError)

struct FileHandleOutputStream: TextOutputStream {
    let fileHandle: FileHandle

    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

// MARK: - Array Extension for Batching

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
