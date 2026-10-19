#!/bin/bash
set -euo pipefail

# Builds a local diagnostic app, without installing or publishing it.
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <signing-identity> <absolute-work-directory> [build-number]" >&2
    exit 2
fi
identity="$1"
work_dir="$2"
build_number="${3:-2202}"
[[ "$work_dir" = /* ]] || { echo "Work directory must be absolute" >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "Build number must be numeric" >&2; exit 2; }
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$work_dir"

xcodebuild build -quiet \
    -project "$repo_dir/Phosphene.xcodeproj" -scheme Phosphene \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$work_dir/DerivedData" \
    -clonedSourcePackagesDirPath "$work_dir/SourcePackages" \
    CURRENT_PROJECT_VERSION="$build_number" \
    ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO

# Sign outside a potentially cloud-managed work directory: File Provider can
# reattach Finder metadata while codesign is traversing a nested bundle.
stage="$(mktemp -d "${TMPDIR:-/tmp}/phosphene-signed.XXXXXX")"
app="$stage/Phosphene.app"
ditto --noextattr "$work_dir/DerivedData/Build/Products/Debug/Phosphene.app" "$app"
# File Provider may attach Finder metadata even to a --noextattr copy. This is a
# newly built staging bundle; remove that metadata before creating signatures.
xattr -cr "$app"
extension="$app/Contents/Extensions/PhospheneExtension.appex"
cat > "$stage/extension.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST

# No split Debug dylib may remain in the package. Avoid relying on --deep signing.
if find "$app" -name '*.debug.dylib' -print | /usr/bin/grep -q .; then
    echo "Unexpected split Debug dylib" >&2
    exit 1
fi
while IFS= read -r -d '' binary; do
    file -b "$binary" | /usr/bin/grep -q 'Mach-O' || continue
    case "$binary" in
        "$app/Contents/MacOS/Phosphene"|"$extension/Contents/MacOS/PhospheneExtension") continue ;;
    esac
    codesign --force --options runtime --timestamp --sign "$identity" "$binary"
done < <(find "$app" -type f -print0)
codesign --force --options runtime --timestamp --sign "$identity" \
    --entitlements "$stage/extension.entitlements" "$extension"
codesign --force --options runtime --timestamp --sign "$identity" \
    --entitlements "$repo_dir/Phosphene/Phosphene.entitlements" "$app"

codesign --verify --deep --strict "$app"
expected_team="$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n "$expected_team" && "$expected_team" != 'not set' ]] || exit 1
while IFS= read -r -d '' binary; do
    file -b "$binary" | /usr/bin/grep -q 'Mach-O' || continue
    codesign --verify --strict "$binary"
    actual_team="$(codesign -dv "$binary" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    [[ "$actual_team" == "$expected_team" ]] || {
        echo "Team ID mismatch: $binary" >&2
        exit 1
    }
done < <(find "$app" -type f -print0)
echo "Signed local diagnostic app: $app"
echo "Team ID: $expected_team"
echo "Not installed. Registration and a real desktop-surface acquire must still be verified."
