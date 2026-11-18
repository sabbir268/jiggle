#!/bin/bash
# Builds a Release Jiggle.app and packages it as dist/Jiggle-<version>.dmg (+ .sha256).
#
#   scripts/make-dmg.sh                 # build the DMG only
#   scripts/make-dmg.sh --release       # also publish a GitHub Release v<version> with the DMG
#   scripts/make-dmg.sh --release --overwrite   # replace the assets of an existing release
#
# Signing:
#   - If a "Developer ID Application" certificate is in the keychain (or SIGN_IDENTITY is set), the app and DMG
#     are signed with it. If notary credentials exist (NOTARY_PROFILE, default "jiggle-notary", created with
#     `xcrun notarytool store-credentials jiggle-notary`), the DMG is notarized and stapled.
#   - Otherwise the app is signed ad-hoc: it works, but people who download it must allow it once in
#     System Settings → Privacy & Security → Open Anyway.
#
# Version comes from MARKETING_VERSION / CURRENT_PROJECT_VERSION in the Xcode project.
set -euo pipefail

RELEASE=0
OVERWRITE=0
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=1 ;;
        --overwrite) OVERWRITE=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO="sabbir268/jiggle"
NOTARY_PROFILE="${NOTARY_PROFILE:-jiggle-notary}"

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# xcodebuild needs full Xcode, not the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
    [ -d /Applications/Xcode.app ] || die "Xcode not found; install it or set DEVELOPER_DIR"
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ "$RELEASE" = 1 ]; then
    command -v gh >/dev/null || die "gh (GitHub CLI) is required for --release"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
    [ -z "$(git status --porcelain)" ] || die "working tree has uncommitted changes; commit them first"
    git fetch -q origin
    [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] || die "HEAD is not pushed; run: git push"
fi

step "Building Release"
DERIVED="build/dist"
xcodebuild -scheme Jiggle -configuration Release -derivedDataPath "$DERIVED" clean build >"build/dist-build.log" 2>&1 \
    || die "build failed; see build/dist-build.log"
APP_SRC="$DERIVED/Build/Products/Release/Jiggle.app"
PLIST="$APP_SRC/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
TAG="v$VERSION"
echo "Jiggle $VERSION ($BUILD)"

STAGE="build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto "$APP_SRC" "$STAGE/Jiggle.app"
APP="$STAGE/Jiggle.app"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi

# Re-sign without entitlements: drops get-task-allow (added by local signing; rejected by notarization).
if [ -n "$IDENTITY" ]; then
    step "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    SIGNED=developer-id
else
    step "Signing ad-hoc (no Developer ID certificate found)"
    codesign --force --options runtime --sign - "$APP"
    SIGNED=ad-hoc
fi
codesign --verify --strict "$APP"

step "Creating DMG"
ln -s /Applications "$STAGE/Applications"
DMG="dist/Jiggle-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Jiggle $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

NOTARIZED=0
if [ "$SIGNED" = developer-id ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        step "Notarizing (this can take a few minutes)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        NOTARIZED=1
    else
        warn "no notary credentials '$NOTARY_PROFILE'; DMG is signed but not notarized"
    fi
fi

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
step "Done: $DMG ($SIGNED$([ "$NOTARIZED" = 1 ] && echo ', notarized'))"
cat "$DMG.sha256"

[ "$RELEASE" = 1 ] || exit 0

step "Publishing GitHub Release $TAG"
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
    echo "## Install"
    echo
    echo "1. Open \`Jiggle-$VERSION.dmg\` and drag **Jiggle** onto **Applications**."
    echo "2. Launch Jiggle from Applications. It lives in the menu bar (no Dock icon)."
    if [ "$NOTARIZED" != 1 ]; then
        echo "3. This build is not notarized by Apple, so macOS blocks the first launch. Open"
        echo "   **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Jiggle."
        echo "   Or run: \`xattr -dr com.apple.quarantine /Applications/Jiggle.app\`"
    fi
    echo
    echo "Jiggle and Jiggle + Click modes need Accessibility permission; Jiggle asks for it when you pick them."
    echo
    echo "Requires macOS 13 or later. SHA-256: \`$(cut -d' ' -f1 "$DMG.sha256")\`"
} > "$NOTES"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    [ "$OVERWRITE" = 1 ] || die "release $TAG already exists; bump MARKETING_VERSION or pass --overwrite"
    gh release upload "$TAG" "$DMG" "$DMG.sha256" -R "$REPO" --clobber
    gh release edit "$TAG" -R "$REPO" --notes-file "$NOTES"
else
    gh release create "$TAG" "$DMG" "$DMG.sha256" -R "$REPO" \
        --target "$(git rev-parse HEAD)" --title "Jiggle $VERSION" --notes-file "$NOTES"
fi
gh release view "$TAG" -R "$REPO" --json url --jq .url
