#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"
app_dir="$dist_dir/Ramlet.app"
archive_path="$dist_dir/Ramlet-macOS-arm64.zip"

cd "$project_dir"
cargo build --release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/target/release/ramlet" "$app_dir/Contents/MacOS/ramlet"
cp "$project_dir/macos/Info.plist" "$app_dir/Contents/Info.plist"
chmod 755 "$app_dir/Contents/MacOS/ramlet"

codesign --force --deep --sign - "$app_dir"
rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive_path"

echo "$app_dir"
echo "$archive_path"

