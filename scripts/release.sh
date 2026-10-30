#!/bin/bash
# Builds, signs, notarizes and packages a release of Pane for Glasshouse into dist/.
# Usage: scripts/release.sh [--publish]
#   (no option): produces the DMG, appcast.xml and cask in dist/, then stops.
#   --publish:   also tags v<version>, pushes it to the `github` remote and
#                creates the GitHub release with the DMG and appcast.xml.
set -euo pipefail

PUBLISH=0
case "${1:-}" in
  "") ;;
  --publish) PUBLISH=1 ;;
  *) echo "usage: release.sh [--publish]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="Developer ID Application: SYNLINK (K4F596J493)"
TEAM="K4F596J493"
PROFILE="pane-notary"
REPO="denisvinciguerra/pane-for-glasshouse"
APP_NAME="Pane for Glasshouse"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
# The EdDSA private key that signs the appcast. When this file is absent,
# generate_appcast reads the key from the keychain.
SPARKLE_KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.config/pane/sparkle-private-key}"

step() { echo; echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

# 1. Guards
step "Checking the repository"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "not on branch main"
VERSION="$(awk '/^ *MARKETING_VERSION:/ { print $2; exit }' project.yml | tr -d "\"'")"
BUILD="$(awk '/^ *CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml | tr -d "\"'")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "invalid MARKETING_VERSION in project.yml: '$VERSION'"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "invalid CURRENT_PROJECT_VERSION in project.yml: '$BUILD'"
NOTES="ReleaseNotes/$VERSION.html"
[ -f "$NOTES" ] || die "missing $NOTES"
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  die "tag v$VERSION already exists"
fi
if [ "$PUBLISH" -eq 1 ]; then
  git remote get-url github >/dev/null || die "no git remote named github"
  gh auth status >/dev/null || die "gh is not authenticated"
fi
echo "version $VERSION (build $BUILD)"

DMG_NAME="Pane-for-Glasshouse-$VERSION.dmg"
ARCHIVE="build/Pane.xcarchive"
EXPORT="build/export"
APP="$EXPORT/$APP_NAME.app"

# 2. Project and tests
step "Generating the project and running the tests"
xcodegen generate
swift test --package-path PaneKit

# 3. Archive and export
step "Archiving"
rm -rf "$ARCHIVE" "$EXPORT" dist
mkdir -p dist/feed
xcodebuild -resolvePackageDependencies -scmProvider system \
  -project Pane.xcodeproj -scheme Pane \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -derivedDataPath build/DerivedData
[ -x "$SPARKLE_BIN/generate_appcast" ] || die "generate_appcast not found in $SPARKLE_BIN"
xcodebuild archive -scmProvider system \
  -project Pane.xcodeproj -scheme Pane -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp \
  ENABLE_HARDENED_RUNTIME=YES
step "Exporting"
xcodebuild -exportArchive -scmProvider system \
  -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions.plist

# 4. Verify the signature, then notarize the app
step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
for target in "$APP" "$APP/Contents/Frameworks/Sparkle.framework"; do
  details="$(codesign -dv --verbose=2 "$target" 2>&1)"
  grep -q 'flags=.*runtime' <<< "$details" \
    || die "hardened runtime flag missing on $target"
done

notarize() { # path
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

step "Notarizing the app"
ditto -c -k --keepParent "$APP" build/Pane-notarize.zip
notarize build/Pane-notarize.zip | tee build/notarize-app.log
grep -q "status: Accepted" build/notarize-app.log || die "app notarization was not accepted (see build/notarize-app.log)"
xcrun stapler staple "$APP"

# 5. DMG
step "Building the DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "dist/$DMG_NAME"
codesign --sign "$IDENTITY" --timestamp "dist/$DMG_NAME"
notarize "dist/$DMG_NAME" | tee build/notarize-dmg.log
grep -q "status: Accepted" build/notarize-dmg.log || die "DMG notarization was not accepted (see build/notarize-dmg.log)"
xcrun stapler staple "dist/$DMG_NAME"

# 6. Appcast
step "Generating the appcast"
cp "dist/$DMG_NAME" dist/feed/
cp "$NOTES" "dist/feed/Pane-for-Glasshouse-$VERSION.html"
# The previous appcast keeps older versions in the feed. It is absent on the
# first release (and while the GitHub repository doesn't exist yet).
if GH_ERR="$(gh release download --repo "$REPO" --pattern appcast.xml --dir dist/feed 2>&1 >/dev/null)"; then
  echo "previous appcast downloaded"
elif grep -qiE 'release not found|no assets match|could not resolve to a repository|repository not found|HTTP 404' <<< "$GH_ERR"; then
  echo "no previous appcast, starting a new feed"
else
  die "gh release download failed: $GH_ERR"
fi
KEY_ARGS=()
[ -f "$SPARKLE_KEY_FILE" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
"$SPARKLE_BIN/generate_appcast" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --embed-release-notes dist/feed
cp dist/feed/appcast.xml dist/appcast.xml
grep -q 'sparkle:edSignature' dist/appcast.xml || die "appcast has no sparkle:edSignature"
grep -q "releases/download/v$VERSION/" dist/appcast.xml || die "appcast has no releases/download/v$VERSION/ URL"
grep -q '<description>' dist/appcast.xml || die "appcast has no embedded release notes"

# 7. Cask
step "Writing the cask"
SHA="$(shasum -a 256 "dist/$DMG_NAME" | awk '{ print $1 }')"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" scripts/cask.rb.template > dist/pane-for-glasshouse.rb
# brew style only applies the cask rules (and skips the Sorbet ones) to files under a Casks/ directory.
mkdir -p build/Casks
cp dist/pane-for-glasshouse.rb build/Casks/
brew style build/Casks/pane-for-glasshouse.rb

# 8. Summary
step "Summary"
echo "DMG:     $ROOT/dist/$DMG_NAME"
echo "Appcast: $ROOT/dist/appcast.xml"
echo "Cask:    $ROOT/dist/pane-for-glasshouse.rb"
echo "sha256:  $SHA"
xcrun stapler validate "$APP"
xcrun stapler validate "dist/$DMG_NAME"
SPCTL_DMG="$(spctl -a -vv -t install "dist/$DMG_NAME" 2>&1)" || true
SPCTL_APP="$(spctl -a -vv "$APP" 2>&1)" || true
echo "$SPCTL_DMG"
echo "$SPCTL_APP"
grep -q 'Notarized Developer ID' <<< "$SPCTL_DMG" || die "the DMG is not accepted as Notarized Developer ID"
grep -q 'Notarized Developer ID' <<< "$SPCTL_APP" || die "the app is not accepted as Notarized Developer ID"

if [ "$PUBLISH" -eq 1 ]; then
  step "Publishing v$VERSION"
  # gh creates the tag on GitHub, so a failure leaves no tag behind.
  gh release create "v$VERSION" --repo "$REPO" --target "$(git rev-parse HEAD)" --title "Pane for Glasshouse $VERSION" \
    --notes-file "$NOTES" "dist/$DMG_NAME" dist/appcast.xml
  git fetch github tag "v$VERSION"
fi
