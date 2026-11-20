#!/usr/bin/env bash
set -euo pipefail
mobile_root="$(cd "$(dirname "$0")/.." && pwd)"
app_root="$mobile_root/apps/mobile"
flutter_command="${FLUTTER_BIN:-flutter}"
if ! command -v "$flutter_command" >/dev/null 2>&1; then
  echo 'Flutter is required. Install pinned stable 3.47.9 or set FLUTTER_BIN to its executable.' >&2
  exit 1
fi
temporary_runner="$(mktemp -d)"
trap 'rm -rf "$temporary_runner"' EXIT
"$flutter_command" create --platforms ios,android,linux --project-name crispy_crust \
  --org app.crispycrust --no-pub "$temporary_runner/runner"
for platform in ios android linux; do
  if [ ! -d "$app_root/$platform" ]; then
    cp -R "$temporary_runner/runner/$platform" "$app_root/$platform"
  fi
done
if [ ! -f "$app_root/.metadata" ]; then
  cp "$temporary_runner/runner/.metadata" "$app_root/.metadata"
fi
python3 "$mobile_root/scripts/configure_platforms.py"
cp "$mobile_root/content/catalogue.json" "$app_root/assets/catalogue.json"
if [ "$(uname -s)" = "Darwin" ]; then
  ruby "$mobile_root/scripts/embed_apple_targets.rb"
fi
echo 'Native runners generated without replacing application code or pubspec.'
