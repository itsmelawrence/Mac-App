#!/bin/bash
# Build, verify, back up, and install a JARVIS Dashboard release.
#
#   scripts/release.sh 0.2.28            build, verify, package, install
#   scripts/release.sh 0.2.28 --commit   same, then commit the version bump
#   scripts/release.sh 0.2.28 --no-install   stop after packaging
#
# Every step is a gate: the script stops at the first failure. The installed app
# is replaced only after tests, build, signature, and backups have all passed.
set -euo pipefail

VERSION="${1:-}"
shift || true
INSTALL=1
COMMIT=0
for arg in "$@"; do
    case "$arg" in
        --no-install) INSTALL=0 ;;
        --commit) COMMIT=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.skeemadigital.jarvisdashboard"
APP_NAME="JARVIS Dashboard.app"
INSTALLED="/Applications/$APP_NAME"
BUILT=".build/xcode/Build/Products/Release/JarvisDashboard.app"
ZIP="dist/JARVIS-Dashboard-$VERSION.zip"
STORES=(
    "global|$HOME/Library/Application Support"
    "container|$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support"
)
BINARY="Contents/MacOS/JarvisDashboard"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nRELEASE STOPPED: %s\n' "$*" >&2; exit 1; }

# --- 1. Preconditions: nothing is changed until all of these pass. ----------
step "Checking preconditions"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: scripts/release.sh X.Y.Z [--commit] [--no-install]"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean; commit or stash first"
CURRENT=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
BUILD_NUMBER=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
[[ -n "$CURRENT" && -n "$BUILD_NUMBER" ]] || fail "could not read the version from project.yml"
NEWEST=$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
[[ "$VERSION" != "$CURRENT" && "$NEWEST" == "$VERSION" ]] || fail "$VERSION is not newer than $CURRENT"
[[ ! -e "$ZIP" ]] || fail "$ZIP already exists"
security find-identity -v -p codesigning | grep -q "Apple Development" \
    || fail "no valid Apple Development signing identity (see the JARVIS hub Notes: WWDR G3)"
echo "Releasing $CURRENT -> $VERSION (build $((BUILD_NUMBER + 1)))"

# --- 2. Version, tests, build. -----------------------------------------------
step "Bumping project.yml"
sed -i '' -e "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$VERSION\"/" \
          -e "s/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/CURRENT_PROJECT_VERSION: \"$((BUILD_NUMBER + 1))\"/" project.yml
grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml || fail "version bump did not apply"

step "Running tests"
TEST_OUTPUT=$(swift test 2>&1) || { echo "$TEST_OUTPUT" | tail -20; fail "tests failed"; }
echo "$TEST_OUTPUT" | grep -E "Test run with" | tail -1

step "Generating Xcode project and building universal Release"
xcodegen generate >/dev/null
xcodebuild -project JarvisDashboard.xcodeproj -scheme JarvisDashboard -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build >.build/release-build.log 2>&1 \
    || fail "xcodebuild failed; see .build/release-build.log"

# --- 3. Verify the build. -------------------------------------------------------
step "Verifying signature, architectures, and version"
codesign --verify --strict "$BUILT" || fail "strict codesign verification failed"
codesign -dr - "$BUILT" 2>&1 | grep -q "anchor apple generic" \
    || fail "build is not signed with the Apple Development identity (ad-hoc?)"
ARCHS=$(lipo -archs "$BUILT/$BINARY")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "expected a universal binary, got: $ARCHS"
BUILT_VERSION=$(defaults read "$ROOT/$BUILT/Contents/Info" CFBundleShortVersionString)
[[ "$BUILT_VERSION" == "$VERSION" ]] || fail "built version is $BUILT_VERSION, expected $VERSION"
echo "Signed, universal ($ARCHS), version $BUILT_VERSION"

step "Packaging $ZIP"
mkdir -p dist
ditto -c -k --keepParent "$BUILT" "$ZIP"
unzip -tq "$ZIP" >/dev/null || fail "zip integrity check failed"

if [[ $INSTALL -eq 0 ]]; then
    step "Done (--no-install): $ZIP"
    exit 0
fi

# --- 4. Back up and install. ------------------------------------------------------
step "Quitting JARVIS"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -f "$APP_NAME/$BINARY" >/dev/null || break; sleep 0.5; done
pgrep -f "$APP_NAME/$BINARY" >/dev/null && fail "JARVIS did not quit; close it and rerun"

BACKUP="dist/install-backups/pre-$VERSION-$(date +%F)"
step "Backing up the installed app and data stores to $BACKUP"
[[ ! -e "$BACKUP" ]] || fail "$BACKUP already exists"
mkdir -p "$BACKUP"
if [[ -d "$INSTALLED" ]]; then
    ditto "$INSTALLED" "$BACKUP/JARVIS Dashboard-$CURRENT.app"
fi
CHECK_DIR=$(mktemp -d)
for entry in "${STORES[@]}"; do
    label="${entry%%|*}"; dir="${entry#*|}"
    [[ -f "$dir/default.store" ]] || continue
    mkdir -p "$CHECK_DIR/$label"
    for suffix in "" "-shm" "-wal"; do
        src="$dir/default.store$suffix"
        [[ -f "$src" ]] || continue
        cp -p "$src" "$BACKUP/$label-default.store$suffix-backup"
        cmp -s "$src" "$BACKUP/$label-default.store$suffix-backup" || fail "backup of $src does not match"
        cp "$src" "$CHECK_DIR/$label/default.store$suffix"
    done
    result=$(sqlite3 "$CHECK_DIR/$label/default.store" "pragma quick_check;")
    [[ "$result" == "ok" ]] || fail "$label store backup failed quick_check: $result"
    echo "$label store backed up and checked"
done
rm -rf "$CHECK_DIR"

step "Installing to $INSTALLED"
CRASHES_BEFORE=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -ci jarvis || true)
rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"
codesign --verify --strict "$INSTALLED" || fail "installed app fails codesign (backup: $BACKUP)"
cmp -s "$BUILT/$BINARY" "$INSTALLED/$BINARY" || fail "installed binary differs from the build (backup: $BACKUP)"

step "Launching and checking"
open "$INSTALLED"
sleep 6
pgrep -f "$APP_NAME/$BINARY" >/dev/null || fail "JARVIS is not running after launch (backup: $BACKUP)"
CRASHES_AFTER=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -ci jarvis || true)
[[ "$CRASHES_AFTER" == "$CRASHES_BEFORE" ]] || fail "a new JARVIS crash report appeared (backup: $BACKUP)"
for entry in "${STORES[@]}"; do
    dir="${entry#*|}"
    [[ -f "$dir/default.store" ]] || continue
    [[ "$(sqlite3 -readonly "$dir/default.store" "pragma quick_check;")" == "ok" ]] \
        || fail "live store ${entry%%|*} failed quick_check after launch (backup: $BACKUP)"
done
echo "Running, no new crash reports, stores healthy"

if [[ $COMMIT -eq 1 ]]; then
    step "Committing the version bump"
    git add project.yml JarvisDashboard.xcodeproj
    git commit -q -m "Release $VERSION"
    git log --oneline -1
fi

step "Released $VERSION. Rollback: quit JARVIS, then copy $BACKUP/JARVIS Dashboard-$CURRENT.app to $INSTALLED"
