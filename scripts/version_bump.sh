#!/bin/bash
# Script để tăng version trong pubspec.yaml
# Usage: ./scripts/version_bump.sh [major|minor|patch]

if [ $# -eq 0 ]; then
    echo "Usage: $0 [major|minor|patch]"
    echo "  major: Tăng MAJOR version (1.0.0 -> 2.0.0)"
    echo "  minor: Tăng MINOR version (1.0.0 -> 1.1.0)"
    echo "  patch: Tăng PATCH version (1.0.0 -> 1.0.1)"
    exit 1
fi

TYPE=$1

if [[ ! "$TYPE" =~ ^(major|minor|patch)$ ]]; then
    echo "Error: Type must be 'major', 'minor', or 'patch'"
    exit 1
fi

PUBSPEC_PATH="pubspec.yaml"

if [ ! -f "$PUBSPEC_PATH" ]; then
    echo "Error: pubspec.yaml not found!"
    exit 1
fi

# Đọc version hiện tại
CURRENT_VERSION=$(grep -E "^version:" "$PUBSPEC_PATH" | sed -E 's/version:[[:space:]]*//')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not find version in pubspec.yaml"
    exit 1
fi

# Parse version
IFS='+' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
VERSION_NAME="${VERSION_PARTS[0]}"
VERSION_CODE="${VERSION_PARTS[1]}"

IFS='.' read -ra VERSION_NUMS <<< "$VERSION_NAME"
MAJOR="${VERSION_NUMS[0]}"
MINOR="${VERSION_NUMS[1]}"
PATCH="${VERSION_NUMS[2]}"

echo "Current version: $MAJOR.$MINOR.$PATCH+$VERSION_CODE"

# Tăng version theo type
case $TYPE in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        echo "Bumping MAJOR version"
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        echo "Bumping MINOR version"
        ;;
    patch)
        PATCH=$((PATCH + 1))
        echo "Bumping PATCH version"
        ;;
esac

# Luôn tăng versionCode
VERSION_CODE=$((VERSION_CODE + 1))

NEW_VERSION="$MAJOR.$MINOR.$PATCH+$VERSION_CODE"

# Thay thế version trong file
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^version:.*/version: $NEW_VERSION/" "$PUBSPEC_PATH"
else
    # Linux
    sed -i "s/^version:.*/version: $NEW_VERSION/" "$PUBSPEC_PATH"
fi

echo "Version updated to: $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Review the changes in pubspec.yaml"
echo "  2. Commit the version change"
echo "  3. Build your app: flutter build apk --release"

