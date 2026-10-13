#!/bin/bash
# Builds, signs, notarizes and packages Kombucha.app for distribution outside the Mac App Store.
# Usage: scripts/release.sh --team TEAMID [--identity NAME] [--profile NAME] [--build N]
#                           [--no-notarize] [--allow-dirty] [--timeout MINUTES] [--resume ID]
#
#   --team ID        Team ID that owns the Developer ID Application certificate (required).
#   --identity NAME  Signing identity. Default: the team's "Developer ID Application" certificate.
#   --profile NAME   notarytool keychain profile. Default: kombucha-notary.
#   --build N        CFBundleVersion. Default: KOMBUCHA_BUILD from Config.
#   --no-notarize    Sign and verify only. The zip is named Kombucha-<version>-unnotarized.zip.
#   --allow-dirty    Build with uncommitted changes (the commit hash in the summary may then lie).
#   --timeout MIN    How long to wait for Apple's verdict. Default: 90 minutes.
#   --resume ID      Skip the build and the upload: take the app from an earlier run, wait for that
#                    notarization submission, then staple and package. The script prints the id.
#
# One-time setup of the notarization profile (use an app-specific password or an API key):
#   xcrun notarytool store-credentials kombucha-notary --apple-id ID --team-id TEAMID --password PASSWORD
#   xcrun notarytool store-credentials kombucha-notary --key AuthKey.p8 --key-id KEYID --issuer ISSUER
#
# Output: dist/Kombucha-<version>.zip and dist/Kombucha-<version>.zip.sha256. Needs Xcode 26 and XcodeGen.

set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd)"
derived="$root/build/release/DerivedData"
dist="$root/dist"

team=""
identity=""
profile="kombucha-notary"
build=""
notarize=1
allow_dirty=0
timeout_minutes=90
resume=""

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --team) team="${2:-}"; shift 2 ;;
        --identity) identity="${2:-}"; shift 2 ;;
        --profile) profile="${2:-}"; shift 2 ;;
        --build) build="${2:-}"; shift 2 ;;
        --no-notarize) notarize=0; shift ;;
        --allow-dirty) allow_dirty=1; shift ;;
        --timeout) timeout_minutes="${2:-}"; shift 2 ;;
        --resume) resume="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

[ -n "$team" ] || die "--team is required"
case "$team" in
    [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
    *) die "team ID '$team' is not ten letters or digits" ;;
esac
case "$timeout_minutes" in
    ''|*[!0-9]*) die "--timeout takes a whole number of minutes" ;;
esac
if [ -n "$resume" ] && [ "$notarize" -eq 0 ]; then
    die "--resume and --no-notarize contradict each other"
fi

# The Command Line Tools are not enough and Xcode 16 does not compile the sources: pick Xcode 26.
select_xcode() {
    local candidate major
    for candidate in "${DEVELOPER_DIR:-}" \
        /Applications/Xcode-26.app/Contents/Developer \
        /Applications/Xcode.app/Contents/Developer; do
        [ -n "$candidate" ] && [ -x "$candidate/usr/bin/xcodebuild" ] || continue
        major="$(DEVELOPER_DIR="$candidate" xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9][0-9]*\).*/\1/p')"
        if [ "${major:-0}" -ge 26 ]; then
            export DEVELOPER_DIR="$candidate"
            return 0
        fi
    done
    die "Xcode 26 not found. Set DEVELOPER_DIR to its Contents/Developer folder."
}

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
select_xcode
echo "Xcode: $(xcodebuild -version | head -n 1) at $DEVELOPER_DIR"

app="$derived/Build/Products/Release/Kombucha.app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -z "$resume" ]; then
    if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
        die "the working tree has uncommitted changes (commit them or pass --allow-dirty)"
    fi

    if [ -z "$identity" ]; then
        identity="$(security find-identity -v -p codesigning \
            | sed -n "s/.*\"\(Developer ID Application: .*($team)\)\".*/\1/p" | head -n 1)"
        [ -n "$identity" ] || die "no 'Developer ID Application' certificate for team $team in the keychain"
    fi
    echo "Identity: $identity"

    step "Generating the project"
    xcodegen generate

    step "Building Release"
    rm -rf "$derived"
    build_args=()
    [ -n "$build" ] && build_args=(KOMBUCHA_BUILD="$build")
    # --timestamp is required for notarization; no base entitlements keeps get-task-allow out.
    xcodebuild -project Kombucha.xcodeproj -scheme Kombucha -configuration Release \
        -derivedDataPath "$derived" \
        KOMBUCHA_TEAM="$team" KOMBUCHA_SIGN_IDENTITY="$identity" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        ${build_args[@]+"${build_args[@]}"} build
else
    step "Resuming submission $resume (no rebuild)"
fi

[ -d "$app" ] || die "no Kombucha.app at $app (build first, without --resume)"
commit="$(git rev-parse --short HEAD)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"

step "Verifying the signature"
scripts/verify-signature.sh "$app" --release

mkdir -p "$dist"

# Each notarytool call signs a fresh token, and the token of one long `submit --wait` expires after
# about 20 minutes (HTTP 401). So submit once, then ask for the status in short calls.
notarize_app() {
    local submission="$resume" status elapsed=0 failures=0 interval=30 limit=$((timeout_minutes * 60))

    if [ -z "$submission" ]; then
        ditto -c -k --keepParent "$app" "$tmp/Kombucha.zip"
        xcrun notarytool submit "$tmp/Kombucha.zip" --keychain-profile "$profile" \
            --output-format plist > "$tmp/submit.plist" \
            || { cat "$tmp/submit.plist" >&2; die "notarytool submit failed"; }
        submission="$(plutil -extract id raw -o - "$tmp/submit.plist")"
        echo "Submitted: $submission"
    fi
    echo "If this script stops, continue with: scripts/release.sh --team $team --resume $submission"

    while :; do
        if xcrun notarytool info "$submission" --keychain-profile "$profile" \
            --output-format plist > "$tmp/info.plist" 2> "$tmp/info.err"; then
            failures=0
            status="$(plutil -extract status raw -o - "$tmp/info.plist")"
            case "$status" in
                Accepted) echo "Accepted, submission $submission"; return 0 ;;
                "In Progress") ;;
                *)
                    xcrun notarytool log "$submission" --keychain-profile "$profile" >&2 || true
                    die "notarization finished with status '$status' (submission $submission)"
                    ;;
            esac
        else
            failures=$((failures + 1))
            echo "warning: notarytool info failed ($failures of 5): $(tr '\n' ' ' < "$tmp/info.err")" >&2
            [ "$failures" -lt 5 ] || die "cannot read the status of submission $submission"
        fi
        [ "$elapsed" -lt "$limit" ] \
            || die "still in progress after $timeout_minutes minutes; continue with --resume $submission"
        if [ $((elapsed % 120)) -eq 0 ]; then
            echo "Waiting for Apple... ${elapsed}s (status: ${status:-unknown})"
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

if [ "$notarize" -eq 1 ]; then
    step "Notarizing (profile $profile)"
    notarize_app

    step "Stapling"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
    zip="$dist/Kombucha-$version.zip"
else
    echo "Skipping notarization (--no-notarize)."
    zip="$dist/Kombucha-$version-unnotarized.zip"
fi

step "Packaging"
rm -f "$zip" "$zip.sha256"
ditto -c -k --keepParent "$app" "$zip"
(cd "$dist" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

echo
echo "Kombucha $version ($build_number), commit $commit (HEAD when this script ran)"
echo "Package: $zip"
echo "SHA-256: $(cut -d ' ' -f 1 "$zip.sha256")"
if [ "$notarize" -eq 0 ]; then
    echo "Not notarized: do not publish this file."
fi
