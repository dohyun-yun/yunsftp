#!/bin/bash
# Updates Casks/yunsftp.rb in the homebrew-yunsftp tap for a published release.
# Usage: scripts/update_cask.sh v1.2.0 [path/to/tap-checkout]
set -euo pipefail
TAG="${1:?usage: update_cask.sh <tag> [tap-dir]}"
VERSION="${TAG#v}"
TAP_DIR="${2:-$(mktemp -d)/homebrew-yunsftp}"
URL="https://github.com/dohyun-yun/yunsftp/releases/download/${TAG}/yunsftp-${TAG}-macos-arm64.dmg"

SHA=$(curl -sL "$URL" | shasum -a 256 | cut -d' ' -f1)
[ -n "$SHA" ] || { echo "could not download $URL"; exit 1; }

if [ ! -d "$TAP_DIR/.git" ]; then
    git clone -q "https://${TAP_GITHUB_TOKEN:+${TAP_GITHUB_TOKEN}@}github.com/dohyun-yun/homebrew-yunsftp.git" "$TAP_DIR"
fi
CASK="$TAP_DIR/Casks/yunsftp.rb"
sed -i '' -e "s/^  version \".*\"/  version \"${VERSION}\"/" -e "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK" 2>/dev/null \
  || sed -i -e "s/^  version \".*\"/  version \"${VERSION}\"/" -e "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"

cd "$TAP_DIR"
git -c user.name=yunsftp-release -c user.email=release@users.noreply.github.com commit -qam "yunsftp ${VERSION}" || { echo "cask already up to date"; exit 0; }
git push -q
echo "cask updated to ${VERSION} (${SHA})"
