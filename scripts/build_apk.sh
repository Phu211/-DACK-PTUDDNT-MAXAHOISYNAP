#!/bin/bash
# Script tự động tăng version và build APK
# Usage: ./scripts/build_apk.sh [patch|minor|major] [--no-version-bump]

VERSION_TYPE=${1:-patch}
NO_VERSION_BUMP=false

# Kiểm tra flag --no-version-bump
if [ "$1" == "--no-version-bump" ] || [ "$2" == "--no-version-bump" ]; then
    NO_VERSION_BUMP=true
    if [ "$1" == "--no-version-bump" ]; then
        VERSION_TYPE=${2:-patch}
    fi
fi

echo "========================================"
echo "  Synap - Auto Build APK Script"
echo "========================================"
echo ""

# Bước 1: Tăng version
if [ "$NO_VERSION_BUMP" = false ]; then
    echo "Step 1: Bumping version ($VERSION_TYPE)..."
    ./scripts/version_bump.sh "$VERSION_TYPE"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to bump version!"
        exit 1
    fi
    echo ""
else
    echo "Step 1: Skipping version bump (--no-version-bump flag)"
    echo ""
fi

# Bước 2: Clean build
echo "Step 2: Cleaning build..."
flutter clean
if [ $? -ne 0 ]; then
    echo "Error: flutter clean failed!"
    exit 1
fi
echo ""

# Bước 3: Get dependencies
echo "Step 3: Getting dependencies..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "Error: flutter pub get failed!"
    exit 1
fi
echo ""

# Bước 4: Build APK
echo "Step 4: Building APK (release)..."
flutter build apk --release
if [ $? -ne 0 ]; then
    echo "Error: Build failed!"
    exit 1
fi
echo ""

# Bước 5: Hiển thị thông tin
echo "========================================"
echo "  Build completed successfully!"
echo "========================================"
echo ""
echo "APK location:"
echo "  build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "To install on device:"
echo "  adb install build/app/outputs/flutter-apk/app-release.apk"
echo ""

