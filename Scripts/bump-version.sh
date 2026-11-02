#!/bin/sh
# Bumps Låda's version everywhere it is recorded, and turns CHANGELOG's "Unreleased" section into
# the new version's section (with today's date) under a fresh, empty "Unreleased".
#
#   Scripts/bump-version.sh minor      # 1.6.0 -> 1.7.0 (new features)
#   Scripts/bump-version.sh patch      # 1.6.0 -> 1.6.1 (fixes)
#   Scripts/bump-version.sh major      # 1.6.0 -> 2.0.0
#   Scripts/bump-version.sh 1.8.0      # explicit
#
# The build number (CFBundleVersion / CURRENT_PROJECT_VERSION / AppVersion.build) goes up by one.
set -eu

cd "$(dirname "$0")/.."
PLIST=Lada/Resources/Info.plist
PBX=Lada.xcodeproj/project.pbxproj
SWIFT=Lada/App/AppVersion.swift

current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
major=$(echo "$current" | cut -d. -f1)
minor=$(echo "$current" | cut -d. -f2)
patch=$(echo "$current" | cut -d. -f3)

case "${1:-}" in
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
    [0-9]*.[0-9]*.[0-9]*) next="$1" ;;
    *) echo "usage: $0 major|minor|patch|X.Y.Z" >&2; exit 64 ;;
esac
next_build=$((build + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $next" -c "Set :CFBundleVersion $next_build" "$PLIST"
sed -i '' -e "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $next;/" \
          -e "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $next_build;/" "$PBX"
sed -i '' -e "s/static let marketing = \"[0-9.]*\"/static let marketing = \"$next\"/" \
          -e "s/static let build = [0-9]*/static let build = $next_build/" "$SWIFT"

today=$(date +%Y-%m-%d)
if grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    sed -i '' "s/^## \[Unreleased\]$/## [Unreleased]\\
\\
## [$next] - $today/" CHANGELOG.md
fi

echo "Låda $current ($build) -> $next ($next_build)"
