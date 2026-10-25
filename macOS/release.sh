#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: eunkyu lee (WBL49792F2)}"
export RELEASE_TEAM_ID="${RELEASE_TEAM_ID:-WBL49792F2}"
if [[ "${1:-}" != "--resume" ]]; then
    bash build.sh
    python3 - <<'PY'
import datetime, os, pathlib, plistlib, shutil
root = pathlib.Path.cwd()
archive = root / 'build/VideoGameFilter.xcarchive'
if archive.exists(): shutil.rmtree(archive)
app = archive / 'Products/Applications/Video Game Filter.app'
app.parent.mkdir(parents=True)
shutil.copytree(root / 'build/Video Game Filter.app', app)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
(archive / 'Info.plist').write_bytes(plistlib.dumps({
    'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': 'Video Game Filter', 'SchemeName': 'GameCapture',
    'ApplicationProperties': {
        'ApplicationPath': 'Applications/Video Game Filter.app',
        'CFBundleIdentifier': info['CFBundleIdentifier'],
        'CFBundleShortVersionString': info['CFBundleShortVersionString'],
        'CFBundleVersion': info['CFBundleVersion'],
        'SigningIdentity': os.environ['CODE_SIGN_IDENTITY'], 'Team': os.environ['RELEASE_TEAM_ID'],
    },
}))
(root / 'build/ExportOptions.plist').write_bytes(plistlib.dumps({
    'method': 'developer-id', 'destination': 'upload', 'teamID': os.environ['RELEASE_TEAM_ID'],
    'signingStyle': 'manual', 'signingCertificate': os.environ['CODE_SIGN_IDENTITY'],
    'manageAppVersionAndBuildNumber': False,
}))
PY
    xcodebuild -exportArchive -archivePath build/VideoGameFilter.xcarchive -exportOptionsPlist build/ExportOptions.plist -exportPath build/notarized -allowProvisioningUpdates
fi
# If Apple is still processing, rerun with --resume; no new build/submission.
# Xcode refuses to overwrite an older exported app. This directory contains
# generated distribution artifacts only; never reuse stale ZIPs after a failure.
python3 - <<'PYCLEAN'
import pathlib, shutil
output = pathlib.Path('build/release')
if output.exists(): shutil.rmtree(output)
PYCLEAN
xcodebuild -exportNotarizedApp -archivePath build/VideoGameFilter.xcarchive -exportPath build/release
app="$PWD/build/release/Video Game Filter.app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
archs="$(lipo -archs "$app/Contents/MacOS/GameCapture")"
if [[ "$archs" != "arm64" ]]; then
    printf 'Expected arm64 release, got: %s\n' "$archs" >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="Video-Game-Filter-${version}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/build/release/$archive"
(cd build/release && shasum -a 256 "$archive" > SHA256SUMS.txt)
printf '\nRelease: %s\n' "$PWD/build/release/$archive"
