#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is not clean. Commit or stash your changes first."
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "${CURRENT_BRANCH}" != "main" ]]; then
  echo "Current branch is '${CURRENT_BRANCH}'. Switch to 'main' before releasing."
  exit 1
fi

VERSION="$(sed -n 's/^version: //p' pubspec.yaml | head -n 1)"
STABLE_VERSION="${VERSION%%+*}"
TAG_NAME="v${STABLE_VERSION}"

if git rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
  echo "Tag '${TAG_NAME}' already exists. Bump version before cutting a new stable."
  exit 1
fi

echo "Preparing Android stable release:"
echo "  version: ${VERSION}"
echo "  tag:     ${TAG_NAME}"

git fetch origin main --tags
git push origin main
git tag -a "${TAG_NAME}" -m "Stable ${TAG_NAME}"
git push origin "${TAG_NAME}"

cat <<EOF

Triggered GitHub Actions Android stable workflow.

Next:
  1. Open GitHub Actions and wait for the 'Android Stable' workflow to finish.
  2. Check GitHub Releases for the new stable release and APK asset.
EOF
