#!/usr/bin/env bash
set -euo pipefail

# Vercel's Linux builder does not provide Flutter. Set FLUTTER_VERSION to a Git
# tag in Vercel project settings for a pinned SDK; stable is the default.
flutter_home="${HOME}/flutter-sdk"
flutter_version="${FLUTTER_VERSION:-stable}"
if [[ ! -x "${flutter_home}/bin/flutter" ]]; then
  git clone --depth 1 --branch "${flutter_version}" https://github.com/flutter/flutter.git "${flutter_home}"
fi
export PATH="${flutter_home}/bin:${PATH}"
flutter config --no-analytics
flutter precache --web

if [[ "${1:-}" == "--install" ]]; then
  flutter pub get
  exit 0
fi

: "${OMNIA_API_BASE_URL:?Set OMNIA_API_BASE_URL to the public HTTPS API root, including /api}"
if [[ "${OMNIA_API_BASE_URL}" != https://* ]]; then
  echo "OMNIA_API_BASE_URL must use HTTPS for a deployed web app." >&2
  exit 1
fi
flutter build web --release \
  --dart-define=OMNIA_DATA=api \
  --dart-define="OMNIA_API_BASE_URL=${OMNIA_API_BASE_URL}"
