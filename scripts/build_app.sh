#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
app_bundle="$project_root/dist/Spine Image Replacer.app"
zip_file="$project_root/dist/Spine Image Replacer.zip"

cd "$project_root"
swift build -c release

if [[ -e "$app_bundle" ]]; then
  rm -rf -- "$app_bundle"
fi
mkdir -p "$app_bundle/Contents/MacOS"
cp "$project_root/.build/release/SpineImageReplacer" "$app_bundle/Contents/MacOS/SpineImageReplacer"
cp "$project_root/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
codesign --force --deep --sign - "$app_bundle"

if [[ -e "$zip_file" ]]; then
  rm -- "$zip_file"
fi
ditto -c -k --norsrc --keepParent "$app_bundle" "$zip_file"

echo "Built app: $app_bundle"
echo "Shareable zip: $zip_file"
