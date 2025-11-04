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
# Preview what will be translated
.build/release/xcstrings-localizer ~/MyApp/Localizable.xcstrings --dry-run

# Perform the translation
.build/release/xcstrings-localizer ~/MyApp/Localizable.xcstrings
```

## Optional: Install Globally

```bash
# Install to /usr/local/bin
sudo cp .build/release/xcstrings-localizer /usr/local/bin/

# Now use from anywhere
xcstrings-localizer ~/MyApp/Localizable.xcstrings
```

## Common Commands

```bash
# Translate entire file
xcstrings-localizer Localizable.xcstrings

# Translate specific keys
xcstrings-localizer Localizable.xcstrings --keys "Welcome" --keys "Goodbye"

# Force re-translation
xcstrings-localizer Localizable.xcstrings --force

# Use better model (slower, more expensive, higher quality)
xcstrings-localizer Localizable.xcstrings --model gpt-4o

# Preview changes
xcstrings-localizer Localizable.xcstrings --dry-run

# Get help
xcstrings-localizer --help
```

## What It Does

1. ✅ Reads your `.xcstrings` file
2. ✅ Identifies untranslated strings
3. ✅ Translates using OpenAI
4. ✅ Respects `shouldTranslate: false`
5. ✅ Uses comments for context
6. ✅ Preserves placeholders
7. ✅ Saves back to file

## Next Steps

- Read the full [README.md](README.md)
- Integrate with Xcode build phases
- Set up CI/CD automation
- Share the binary with your team

---

**That's it! You're ready to localize.** 🚀
