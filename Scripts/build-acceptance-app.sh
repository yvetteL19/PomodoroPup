#!/bin/bash
# Build the production sources under an isolated local acceptance identity.
# This script never launches an app or reads/writes application preferences.
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ "$#" -ne 0 ]]; then
    if [[ "$#" -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
        printf 'Usage: %s\n' "${0##*/}"
        printf 'Build and verify PomodoroPupQA in /tmp/PomodoroPup-Acceptance; do not launch it.\n'
        exit 0
    fi
    fail 'No build-setting overrides or positional arguments are accepted.'
fi

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail 'This script requires macOS and Xcode.'
[[ -z "${XCODE_XCCONFIG_FILE:-}" ]] || fail 'Unset XCODE_XCCONFIG_FILE so external settings cannot override the acceptance identity.'

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_directory="$(cd -- "$script_directory/.." && pwd -P)"
readonly script_directory project_directory
readonly bundle_identifier='com.pomodoropup.acceptance'
readonly product_name='PomodoroPupQA'
readonly display_name='PomodoroPup QA'
readonly derived_data='/tmp/PomodoroPup-Acceptance'
readonly project_file="$project_directory/PomodoroPup.xcodeproj"
readonly source_entitlements="$project_directory/PomodoroPup/PomodoroPup.entitlements"
readonly app_path="$derived_data/Build/Products/Debug/$product_name.app"
readonly info_path="$app_path/Contents/Info.plist"
readonly build_log="$derived_data/acceptance-build.log"
readonly signed_entitlements="$derived_data/acceptance-entitlements.plist"
readonly signature_log="$derived_data/acceptance-signature.log"

[[ "$bundle_identifier" == 'com.pomodoropup.acceptance' && "$bundle_identifier" != 'Yvette.PomodoroPup' ]] || fail 'Refusing a non-acceptance bundle identity.'
[[ -d "$project_file" && -f "$source_entitlements" ]] || fail 'Project or source entitlements are missing.'
[[ ! -L "$derived_data" && ! -L "$app_path" ]] || fail 'The acceptance build directory and app must not be symbolic links.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$source_entitlements")" == 'true' ]] || fail 'The source app sandbox entitlement must remain enabled.'

/bin/mkdir -p "$derived_data"
resolved_derived_data="$(cd -- "$derived_data" && pwd -P)"
case "$resolved_derived_data" in
    /tmp/PomodoroPup-Acceptance|/private/tmp/PomodoroPup-Acceptance) ;;
    *) fail 'The acceptance DerivedData directory must resolve inside /tmp.' ;;
esac

# Replacing an app on disk does not replace an already loaded process. Refuse
# that ambiguous test setup; do not terminate the user's running QA session.
if ! running_processes="$(/bin/ps -axww -o pid=,comm=)"; then
    fail 'Cannot inspect running processes. Close PomodoroPup QA and rerun from a terminal that permits process inspection.'
fi
readonly qa_executable="$app_path/Contents/MacOS/$product_name"
readonly resolved_qa_executable="$resolved_derived_data/Build/Products/Debug/$product_name.app/Contents/MacOS/$product_name"
while IFS=$' \t' read -r process_id executable; do
    if [[ "$executable" == "$qa_executable" || "$executable" == "$resolved_qa_executable" ]]; then
        fail "PomodoroPup QA is still running (PID $process_id). Quit QA before rebuilding."
    fi
done <<<"$running_processes"

printf 'Building the isolated acceptance app. Build log: %s\n' "$build_log" >&2
if ! /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme PomodoroPup \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    "PRODUCT_BUNDLE_IDENTIFIER=$bundle_identifier" \
    "PRODUCT_NAME=$product_name" \
    "INFOPLIST_KEY_CFBundleDisplayName=$display_name" \
    'DEVELOPMENT_TEAM=' \
    'CODE_SIGN_STYLE=Manual' \
    'CODE_SIGN_IDENTITY=-' \
    'CODE_SIGNING_ALLOWED=YES' \
    build >"$build_log" 2>&1; then
    /usr/bin/tail -n 80 "$build_log" >&2
    fail "Acceptance build failed; full output is in $build_log"
fi

[[ -d "$app_path" && -f "$info_path" && ! -L "$app_path" ]] || fail 'The expected acceptance app was not produced.'
actual_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_path")"
actual_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_path")"
actual_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_path")"
actual_display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_path")"
[[ "$actual_identifier" == "$bundle_identifier" ]] || fail 'Built Info.plist does not contain the acceptance bundle identity.'
[[ "$actual_executable" == "$product_name" && "$actual_name" == "$product_name" && "$actual_display_name" == "$display_name" ]] || fail 'Built product names do not identify the acceptance app.'
[[ -x "$app_path/Contents/MacOS/$product_name" ]] || fail 'The acceptance executable is missing.'

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" >&2
/usr/bin/codesign -d --verbose=4 "$app_path" >"$signature_log" 2>&1
/usr/bin/grep -Fqx "Identifier=$bundle_identifier" "$signature_log" || fail 'The signed identity does not match the acceptance bundle identity.'
/usr/bin/grep -Fqx 'Signature=adhoc' "$signature_log" || fail 'The acceptance app must use local ad-hoc signing.'

# --xml produces a machine-readable plist without the deprecated ":-" spelling.
/usr/bin/codesign -d --entitlements - --xml "$app_path" >"$signed_entitlements" 2>>"$signature_log"
/usr/bin/plutil -lint "$signed_entitlements" >&2
for entitlement in com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only; do
    expected_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$source_entitlements")"
    signed_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$signed_entitlements")"
    [[ "$expected_value" == 'true' && "$signed_value" == "$expected_value" ]] || fail "Required sandbox entitlement was not preserved: $entitlement"
done

printf 'Verified isolated bundle identity, product names, ad-hoc signature, and sandbox entitlements. App was not launched.\n' >&2
printf '%s\n' "$app_path"
