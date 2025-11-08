#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== TranscribeIt .app Bundle Builder ===${NC}\n"

# Configuration
APP_NAME="TranscribeIt"
BUNDLE_ID="com.transcribeit.app"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean previous build
echo -e "${YELLOW}[1/6] Cleaning previous build...${NC}"
rm -rf build
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Build with Swift Package Manager (Release mode)
echo -e "${YELLOW}[2/6] Building Swift executable (Release)...${NC}"
swift build -c release --product TranscribeIt

if [ ! -f "${BUILD_DIR}/TranscribeIt" ]; then
    echo -e "${RED}❌ Build failed: executable not found at ${BUILD_DIR}/TranscribeIt${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"

# Copy executable to app bundle
echo -e "${YELLOW}[3/6] Creating .app bundle structure...${NC}"
cp "${BUILD_DIR}/TranscribeIt" "${MACOS_DIR}/"
chmod +x "${MACOS_DIR}/TranscribeIt"

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "${CONTENTS_DIR}/"
    echo -e "${GREEN}✅ Info.plist copied${NC}"
else
    echo -e "${RED}❌ Info.plist not found${NC}"
    exit 1
fi

# Copy icon if exists (optional for now)
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/"
    echo -e "${GREEN}✅ App icon copied${NC}"
else
    echo -e "${YELLOW}⚠️  No app icon found (Resources/AppIcon.icns), using default${NC}"
fi

# Create PkgInfo file
echo -e "${YELLOW}[4/6] Creating PkgInfo...${NC}"
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Set bundle identifier in Info.plist
echo -e "${YELLOW}[5/6] Verifying Info.plist...${NC}"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "${CONTENTS_DIR}/Info.plist" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    BUNDLE_ID_ACTUAL=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "${CONTENTS_DIR}/Info.plist")
    echo -e "${GREEN}✅ Bundle ID: ${BUNDLE_ID_ACTUAL}${NC}"
else
    echo -e "${RED}❌ Failed to read Bundle ID from Info.plist${NC}"
    exit 1
fi

# Sign the app with ad-hoc signature
echo -e "${YELLOW}[6/7] Signing app bundle...${NC}"

# Sign with entitlements if available
ENTITLEMENTS_FILE="Entitlements.plist"
if [ -f "${ENTITLEMENTS_FILE}" ]; then
    codesign --force --deep --sign - --entitlements "${ENTITLEMENTS_FILE}" "${APP_DIR}" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ App signed with ad-hoc signature + entitlements${NC}"
        echo -e "${GREEN}   Entitlements: ${ENTITLEMENTS_FILE}${NC}"
    else
        # Fallback without entitlements
        codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null
        echo -e "${GREEN}✅ App signed with ad-hoc signature (no entitlements)${NC}"
    fi
else
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null
    echo -e "${GREEN}✅ App signed with ad-hoc signature (no entitlements found)${NC}"
fi

# Verify signature
SIGN_INFO=$(codesign -dvv "${APP_DIR}" 2>&1 | grep "Identifier=" | cut -d= -f2)
echo -e "${GREEN}   Identifier: ${SIGN_INFO}${NC}"

# Verify app bundle structure
echo -e "${YELLOW}[7/7] Verifying .app bundle structure...${NC}"

if [ -d "${APP_DIR}" ]; then
    echo -e "${GREEN}✅ .app bundle created successfully${NC}"

    # Show bundle structure
    echo -e "\n${BLUE}Bundle structure:${NC}"
    echo "build/"
    echo "└── ${APP_NAME}.app/"
    echo "    └── Contents/"
    echo "        ├── Info.plist"
    echo "        ├── PkgInfo"
    echo "        ├── MacOS/"
    echo "        │   └── TranscribeIt (executable)"
    echo "        └── Resources/"
    if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
        echo "            └── AppIcon.icns"
    fi

    # Show app info
    echo -e "\n${BLUE}App Information:${NC}"
    echo "  Name: ${APP_NAME}"
    echo "  Bundle ID: ${BUNDLE_ID_ACTUAL}"
    echo "  Version: $(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONTENTS_DIR}/Info.plist")"
    echo "  Executable: TranscribeIt"
    echo "  Location: $(pwd)/${APP_DIR}"

    # Calculate size
    APP_SIZE=$(du -sh "${APP_DIR}" | cut -f1)
    echo "  Size: ${APP_SIZE}"

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ .app bundle built successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Instructions
    echo -e "\n${BLUE}Next steps:${NC}"
    echo "  1. Test the app: open ${APP_DIR}"

else
    echo -e "${RED}❌ Failed to create .app bundle${NC}"
    exit 1
fi
