# Quick Start Guide (Swift Version)

Get started with XCStrings Localizer in 2 minutes.

## Installation

```bash
cd XCStringsLocalizer

# Build the tool
swift build -c release

# The binary is now at: .build/release/xcstrings-localizer
```

## Setup API Key

```bash
# Create .env file with API key
echo "OPENAI_API_KEY='your-key-here'" > .env

# (Optional but recommended) Add app description for better translations
echo "APP_DESCRIPTION='Your app description here'" >> .env
```

Get your key from: https://platform.openai.com/api-keys

**Pro tip:** Adding an app description improves translation quality significantly!

## First Translation

```bash
# Navigate to your Xcode project directory
cd ~/MyApp

# Preview what will be translated (auto-discovers .xcstrings files)
../XCStringsLocalizer/.build/release/xcstrings-localizer --dry-run

# Perform the translation
../XCStringsLocalizer/.build/release/xcstrings-localizer
```

## Optional: Install Globally

```bash
# Install to /usr/local/bin
sudo cp .build/release/xcstrings-localizer /usr/local/bin/

# Now use from anywhere in your project directories
cd ~/MyApp
xcstrings-localizer
```

## Common Commands

```bash
# Auto-discover and translate all .xcstrings files
xcstrings-localizer

# Translate a specific file
xcstrings-localizer Localizable.xcstrings

# Translate multiple files
xcstrings-localizer Localizable.xcstrings InfoPlist.xcstrings

# Translate specific keys (works with auto-discovery)
xcstrings-localizer --keys "Welcome" --keys "Goodbye"

# Force re-translation of all strings
xcstrings-localizer --force

# Use better model (slower, more expensive, higher quality)
xcstrings-localizer --model gpt-4o

# Preview changes (dry run)
xcstrings-localizer --dry-run

# Get AI suggestions for improving translations
xcstrings-localizer --suggest

# Get help
xcstrings-localizer --help
```

## What It Does

1. ✅ Auto-discovers `.xcstrings` files in your project (or uses specified files)
2. ✅ Reads target languages from your Xcode project's `knownRegions`
3. ✅ Identifies untranslated strings
4. ✅ Translates using OpenAI in efficient batches
5. ✅ Respects `shouldTranslate: false` flags
6. ✅ Uses comments for context
7. ✅ Preserves placeholders (%@, %d, etc.)
8. ✅ Saves translations back to file(s)
9. ✅ Automatically translates files in `localized-extras/` directory

## Bonus: Translate Extra Files

```bash
# Create directory for App Store descriptions, release notes, etc.
mkdir localized-extras

# Add your marketing materials
cp appstore-description.md localized-extras/

# Run localizer - it will translate both .xcstrings AND extras!
xcstrings-localizer

# Result: appstore-description.fr.md, appstore-description.de.md, etc.
```

## Next Steps

- Read the full [README.md](README.md)
- Integrate with Xcode build phases
- Set up CI/CD automation
- Share the binary with your team

---

**That's it! You're ready to localize.** 🚀
