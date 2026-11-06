#!/usr/bin/env bash
# Cuts a release: bumps VERSION, tags and pushes, waits for the GitHub build to
# attach Blink.zip, then points the Homebrew cask at it.
#
#   scripts/release.sh 1.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
REPO=pnborchert/blink
TAP=pnborchert/homebrew-tap

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi

echo "$VERSION" > VERSION
git commit -qam "Release $VERSION"
git tag -a "v$VERSION" -m "Blink $VERSION"
git push -q origin HEAD "v$VERSION"

echo "Waiting for the release build…"
RUN=""
for _ in {1..20}; do
  RUN=$(gh run list -R "$REPO" --branch "v$VERSION" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
  [[ -n "$RUN" ]] && break
  sleep 3
done
[[ -n "$RUN" ]] || { echo "No build started for v$VERSION." >&2; exit 1; }
gh run watch "$RUN" -R "$REPO" --exit-status > /dev/null

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/Blink.zip" "https://github.com/$REPO/releases/download/v$VERSION/Blink.zip"
SHA=$(shasum -a 256 "$TMP/Blink.zip" | cut -d' ' -f1)

gh repo clone "$TAP" "$TMP/tap" -- -q
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TMP/tap/Casks/blink.rb"
git -C "$TMP/tap" commit -qam "blink $VERSION"
git -C "$TMP/tap" push -q

echo "Released Blink $VERSION. Users get it with: brew upgrade --cask blink"
