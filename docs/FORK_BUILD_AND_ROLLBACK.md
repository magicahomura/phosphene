# Building and rolling back the 1.9.0 fork

This guide records the pinned baseline and the local fork build path. It does not
change the app's bundle identifiers or publish an installable release.

## Baseline

- Source tag: `v1.9.0`
- Source commit: `db03edf97143d9f4a5958c36c145cc5a8c111315`
- App: `glass.kagerou.phosphene`, version `1.9.0` (build `22`)
- Extension: `glass.kagerou.phosphene.extension`, version `1.9.0` (build `22`)
- Swift packages are pinned by `Phosphene.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Build the source without signing

Use an isolated DerivedData directory and package clone cache so stale Xcode
checkouts cannot affect the result:

```sh
REPO="$(pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/phosphene-derived-data"
PACKAGE_CACHE="${TMPDIR:-/tmp}/phosphene-package-clones"

xcodebuild \
  -project "$REPO/Phosphene.xcodeproj" \
  -scheme Phosphene \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$PACKAGE_CACHE" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The unsigned build validates source compilation only. It is not suitable for
installing the wallpaper extension. Before installation, sign the app and
embedded extension with an identity accepted by this macOS installation, then
verify both signatures, extension registration, and the updater behavior.

## Build a signed local diagnostic app

Run `scripts/build-local-diagnostic.sh <identity> <absolute-work-directory>
[build-number]` with an identity available in the local keychain. The script
builds Debug with `ENABLE_DEBUG_DYLIB=NO`, so the executable contains its code
instead of depending on Xcode's split Debug dylib. Debug disables the existing
automatic and in-place updater paths. This is a local diagnostic package, not
a notarized release.

The script signs embedded Mach-O code before the extension and application
bundles, preserves the extension sandbox and manager bookmark entitlement, and
checks every Mach-O file for the same nonempty Team ID. Do not disable library
validation to make a mixed-signature package launch. A strict bundle signature
check alone can pass even when dyld rejects an unsigned/ad-hoc Debug dylib at
launch. Installation acceptance requires a fresh extension INIT and desktop
surface ACQUIRE, no new dyld crash, and the expected diagnostic records.

The signing stage is created in the system temporary directory to prevent cloud
File Provider metadata from being attached while codesign traverses the bundle.
Install the verified bundle as a complete replacement, then explicitly register
the installed extension with `pluginkit -a
/Applications/Phosphene.app/Contents/Extensions/PhospheneExtension.appex`. Inspect
`pluginkit -mAvvv -i glass.kagerou.phosphene.extension` and ensure its path points
to the installed app. Unregister only known temporary staging copies if they
were previously opened; a stale staging registration can otherwise be selected.

Local validation on 2026-10-19: build 2202 passed the per-Mach-O Team ID and
signature checks, started the installed extension, acquired desktop surfaces for
both displays (2048×1152@2 and 1080×1920@2), emitted first-frame-ready geometry
records, and started both renderers unpaused. This validates extension loading;
physical display recovery and visual acceptance remain separate checks.

## Local backup before replacing the installed app

Keep the backup outside the repository and include:

- the complete original `Phosphene.app` bundle;
- the extension's `phosphene-prefs.json` and current `phosphene-state.json`;
- the app and extension preference plists;
- a text capture of `pluginkit -mAv` for the extension;
- app and extension version, bundle identifier, signing identity, and hashes.

Do not copy or alter the wallpaper video library to make this backup. Its
existing files and Wallpaper settings are user data. Record the current
per-display and Space choices before installation and compare them after.

## Rollback

1. Quit Phosphene and stop the customized extension by restoring the original
   application bundle; let WallpaperAgent reload the extension. Replace the
   complete bundle from a clean staging directory. Do not merge the original
   into an existing custom bundle: stale Debug dylibs and other files can remain.
2. Verify that `glass.kagerou.phosphene` and
   `glass.kagerou.phosphene.extension` are the original version and that the
   original extension is registered and signed.
3. Restore the backed-up Phosphene preference files only if the customized
   version changed them. Preserve any newly added wallpaper media and other
   user changes.
4. Verify the original wallpaper choices and playback on each display.

The app replacement and recovery procedure must be exercised on the target Mac
before treating an installed fork build as accepted.
