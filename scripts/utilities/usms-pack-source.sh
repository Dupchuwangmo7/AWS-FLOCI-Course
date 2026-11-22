#!/usr/bin/env bash
# Pack an application tree into a CodeBuild/CodePipeline source zip.
# buildspec.yml must sit at the ROOT of the archive, so we zip from inside the tree.
# Usage: usms-pack-source.sh <app-dir> <output.zip>
set -euo pipefail
APP_DIR="${1:?usage: usms-pack-source.sh <app-dir> <output.zip>}"
OUT="${2:?usage: usms-pack-source.sh <app-dir> <output.zip>}"
[ -f "$APP_DIR/buildspec.yml" ] || { echo "no buildspec.yml in $APP_DIR" >&2; exit 1; }
case "$OUT" in /*) ABS_OUT="$OUT" ;; *) ABS_OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$ABS_OUT")"
rm -f "$ABS_OUT"
( cd "$APP_DIR" && zip -qr "$ABS_OUT" . -x 'dist/*' -x '.DS_Store' -x '*/.DS_Store' )
echo "packed $APP_DIR -> $OUT"
unzip -l "$ABS_OUT"
unzip -l "$ABS_OUT" | awk '{print $4}' | grep -qx 'buildspec.yml' || { echo "buildspec.yml is NOT at the archive root" >&2; exit 1; }
echo "buildspec.yml is at the archive root"
