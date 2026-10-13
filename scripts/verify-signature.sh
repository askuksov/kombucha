#!/bin/bash
# Checks the signature shape of a built Kombucha.app and never signs anything.
# Usage: scripts/verify-signature.sh path/to/Kombucha.app [--release]

set -u

app="${1:-}"
mode="${2:-}"
release=0
case "$mode" in
    "") ;;
    --release) release=1 ;;
    *)
        echo "usage: $0 path/to/Kombucha.app [--release]" >&2
        exit 2
        ;;
esac

if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "usage: $0 path/to/Kombucha.app [--release]" >&2
    exit 2
fi

app_id="dev.kuksov.kombucha"
helper_id="dev.kuksov.kombucha.helper"
helper="$app/Contents/MacOS/kombucha-helper"
job="$app/Contents/Library/LaunchDaemons/$helper_id.plist"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
info() { echo "info  $1"; }

signing_field() {
    codesign -dv "$1" 2>&1 | sed -n "s/^$2=//p" | head -n 1
}

# PlistBuddy prints "File Doesn't Exist" and exits 0 for a missing file, so check the file first.
plist_value() {
    [ -f "$1" ] || return 1
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

expect_plist() {
    local file="$1" key="$2" expected="$3" actual
    if actual="$(plist_value "$file" "$key")" && [ "$actual" = "$expected" ]; then
        pass "$(basename "$file") $key = $expected"
    else
        fail "$(basename "$file") $key is '${actual:-missing}', expected '$expected'"
    fi
}

entitlement_keys() {
    local binary="$1"
    # -e, not -f: this is called with both the .app bundle (a directory) and the raw helper binary.
    if [ ! -e "$binary" ]; then
        echo "entitlement_keys: no such file: $binary" >&2
        return 1
    fi
    if ! codesign -d --entitlements - --xml "$binary" > "$tmp/entitlements.plist" 2>/dev/null; then
        echo "entitlement_keys: codesign -d failed on: $binary" >&2
        return 1
    fi
    [ -s "$tmp/entitlements.plist" ] || return 0
    plutil -p "$tmp/entitlements.plist" | sed -n 's/^  "\([^"]*\)" =>.*/\1/p' | sort
}

check_entitlements() {
    local label="$1" binary="$2" expected="$3" actual raw status
    raw="$(entitlement_keys "$binary")"
    status=$?
    if [ "$status" -ne 0 ]; then
        fail "$label entitlements: could not read (see entitlement_keys error above)"
        return
    fi
    actual="$(echo "$raw" | grep -vx 'com.apple.security.get-task-allow')"
    if [ "$actual" = "$expected" ]; then
        pass "$label entitlements: ${expected:-none}"
    else
        fail "$label entitlements are '$(echo "$actual" | tr '\n' ' ')', expected '${expected:-none}'"
    fi
    if [ "$release" -eq 1 ] && echo "$raw" | grep -qx 'com.apple.security.get-task-allow'; then
        fail "$label carries get-task-allow in a release build"
    fi
}

if codesign --verify --deep --strict "$app" 2>"$tmp/verify.txt"; then
    pass "codesign --verify --deep --strict"
else
    fail "codesign --verify --deep --strict: $(tr '\n' ' ' < "$tmp/verify.txt")"
fi

check_identifier_and_runtime() {
    local binary="$1" expected="$2" actual
    actual="$(signing_field "$binary" Identifier)"
    if [ "$actual" = "$expected" ]; then pass "identifier $expected"; else fail "identifier is '$actual', expected '$expected'"; fi
    if codesign -dv "$binary" 2>&1 | grep -q '^CodeDirectory.*flags=.*runtime'; then
        pass "hardened runtime on $expected"
    else
        fail "no hardened runtime on $expected"
    fi
}

check_identifier_and_runtime "$app" "$app_id"
check_identifier_and_runtime "$helper" "$helper_id"

app_team="$(signing_field "$app" TeamIdentifier)"
helper_team="$(signing_field "$helper" TeamIdentifier)"
codesign -d --extract-certificates="$tmp/cert" "$app" 2>/dev/null
cert_team="$(openssl x509 -inform DER -in "$tmp/cert0" -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')"
if [ -n "$app_team" ] && [ "$app_team" != "not set" ] && [ "$app_team" = "$helper_team" ] && [ "$app_team" = "$cert_team" ]; then
    pass "team $app_team on app, helper and certificate"
else
    fail "teams differ: app '$app_team', helper '$helper_team', certificate OU '$cert_team'"
fi

check_entitlements "app" "$app" ""
check_entitlements "helper" "$helper" ""

client_requirement="identifier \"$app_id\" and anchor apple generic and certificate leaf[subject.OU] = \"$app_team\""
helper_requirement="identifier \"$helper_id\" and anchor apple generic and certificate leaf[subject.OU] = \"$app_team\""

expect_plist "$app/Contents/Info.plist" KombuchaHelperRequirement "$helper_requirement"
expect_plist "$app/Contents/Info.plist" LSUIElement true
if grep -aqF "$client_requirement" "$helper" 2>/dev/null; then
    pass "helper embeds the client requirement"
else
    fail "helper does not embed: $client_requirement"
fi

# -R with a separate argument is read as a file path; the inline form needs -R=.
if codesign --verify -R="$client_requirement" "$app" 2>/dev/null; then
    pass "app satisfies the client requirement"
else
    fail "app does not satisfy: $client_requirement"
fi
if codesign --verify -R="$helper_requirement" "$helper" 2>/dev/null; then
    pass "helper satisfies the helper requirement"
else
    fail "helper does not satisfy: $helper_requirement"
fi

expect_plist "$job" Label "$helper_id"
expect_plist "$job" BundleProgram "Contents/MacOS/kombucha-helper"
expect_plist "$job" "MachServices:$helper_id" true
expect_plist "$job" "AssociatedBundleIdentifiers:0" "$app_id"

info "spctl: $(spctl -a -vvv -t exec "$app" 2>&1 | tr '\n' ' ')"

if [ "$failures" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$failures check(s) failed"
    exit 1
fi
