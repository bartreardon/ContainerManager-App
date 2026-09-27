#!/bin/bash
# Writes appcast.xml, Sparkle's update feed, beside a notarized ContainerManager.dmg.
# Upload both to the GitHub release; the app reads releases/latest/download/appcast.xml,
# so the feed goes live at the same moment as the release it describes.
#
# Usage: scripts/make-appcast.sh path/to/ContainerManager.dmg [path/to/sign_update]
#
# sign_update comes with Sparkle; by default it's found in Xcode's package cache.
# It signs with the EdDSA private key that generate_keys put in your login keychain.

set -euo pipefail

DMG="${1:?Usage: $0 path/to/ContainerManager.dmg [path/to/sign_update]}"
SIGN_UPDATE="${2:-$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin/sign_update' -print -quit 2>/dev/null)}"
[[ -x "$SIGN_UPDATE" ]] || { echo "sign_update not found; pass its path as the second argument." >&2; exit 1; }

MOUNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
trap 'hdiutil detach -quiet "$MOUNT"; rmdir "$MOUNT"' EXIT

APP=$(find "$MOUNT" -maxdepth 1 -name '*.app' -print -quit)
[[ -n "$APP" ]] || { echo "No app found in $DMG." >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
MINIMUM_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")

# Prints: sparkle:edSignature="…" length="…"
SIGNATURE=$("$SIGN_UPDATE" "$DMG")

TAG="v$VERSION"
RELEASES="https://github.com/bartreardon/ContainerManager-App/releases"
OUTPUT="$(dirname "$DMG")/appcast.xml"

cat >"$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Container Manager</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$RELEASES/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="$RELEASES/download/$TAG/ContainerManager.dmg" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

echo "Wrote $OUTPUT for $VERSION (build $BUILD), tag $TAG."
