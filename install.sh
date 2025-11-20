#!/bin/bash
set -e

# XCStrings Localizer Installation Script
# This script downloads and installs the latest version of xcstrings-localizer

REPO="thillsman/XCStringsLocalizer"
BINARY_NAME="xcstrings-localizer"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR=$(mktemp -d)

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}XCStrings Localizer - Installation${NC}"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This tool only works on macOS${NC}"
    exit 1
fi

# Get latest release info from GitHub
echo -e "${BLUE}Fetching latest release...${NC}"
RELEASE_INFO=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest")

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to fetch release information${NC}"
    exit 1
fi

VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep "browser_download_url.*macos.zip" | cut -d '"' -f 4)

if [ -z "$VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find latest release${NC}"
    exit 1
fi

echo -e "${GREEN}Latest version: ${VERSION}${NC}"
echo ""

# Check if already installed
if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
    CURRENT_VERSION=$("${INSTALL_DIR}/${BINARY_NAME}" --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    echo -e "${YELLOW}Current version: ${CURRENT_VERSION}${NC}"

    if [ "$CURRENT_VERSION" = "${VERSION#v}" ]; then
        echo -e "${GREEN}Already up to date!${NC}"
        read -p "Reinstall anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# Download the binary
echo -e "${BLUE}Downloading ${VERSION}...${NC}"
cd "$TEMP_DIR"
curl -L -o "${BINARY_NAME}.zip" "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to download binary${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Extract the binary
echo -e "${BLUE}Extracting...${NC}"
unzip -q "${BINARY_NAME}.zip"

if [ ! -f "$BINARY_NAME" ]; then
    echo -e "${RED}Error: Binary not found in archive${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Make it executable
chmod +x "$BINARY_NAME"

# Install the binary
echo -e "${BLUE}Installing to ${INSTALL_DIR}...${NC}"
if [ -w "$INSTALL_DIR" ]; then
    mv "$BINARY_NAME" "${INSTALL_DIR}/"
else
    echo -e "${YELLOW}Need sudo permission to install to ${INSTALL_DIR}${NC}"
    sudo mv "$BINARY_NAME" "${INSTALL_DIR}/"
fi

# Clean up
rm -rf "$TEMP_DIR"

# Verify installation
if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
    INSTALLED_VERSION=$("${INSTALL_DIR}/${BINARY_NAME}" --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    echo ""
    echo -e "${GREEN}✓ Successfully installed ${BINARY_NAME} ${VERSION}${NC}"
    echo ""
    echo -e "${BLUE}Try it out:${NC}"
    echo "  ${BINARY_NAME} --help"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Set your OpenAI API key:"
    echo "     export OPENAI_API_KEY='your-key-here'"
    echo "  2. Navigate to your Xcode project directory"
    echo "  3. Run: ${BINARY_NAME}"
    echo ""
    echo -e "${BLUE}To update in the future:${NC}"
    echo "  ${BINARY_NAME} update"
    echo "  or"
    echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
else
    echo -e "${RED}Error: Installation failed${NC}"
    exit 1
fi
