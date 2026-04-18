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
STAMP="$(date +%Y%m%d%H%M)"
LABEL="${1:-}"

TAG_BASE="android-canary-v${VERSION//+/-build.}"
if [[ -n "${LABEL}" ]]; then
  TAG_NAME="${TAG_BASE}-${LABEL}-${STAMP}"
else
  TAG_NAME="${TAG_BASE}-${STAMP}"
fi

echo "Preparing Android canary release:"
echo "  version: ${VERSION}"
echo "  tag:     ${TAG_NAME}"

git fetch origin main --tags
git push origin main
git tag -a "${TAG_NAME}" -m "Android canary ${TAG_NAME}"
git push origin "${TAG_NAME}"

cat <<EOF

Triggered GitHub Actions Android canary workflow.

Next:
  1. Open GitHub Actions and wait for the 'Android Canary' workflow to finish.
  2. Download the APK from the generated pre-release or workflow artifact.
EOF
