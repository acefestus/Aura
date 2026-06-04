#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

printf '\n[1/6] Repo status\n'
git status --short

printf '\n[2/6] Swift syntax and type-check via signing-free build\n'
xcodebuild \
  -project Aura.xcodeproj \
  -scheme Aura \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build > /tmp/aura_release_build.log

tail -n 20 /tmp/aura_release_build.log

printf '\n[3/6] Backend dependency health check\n'
if [[ -d backend ]]; then
  (cd backend && npm run -s build)
else
  echo 'backend/ not found; skipping backend build check.'
fi

printf '\n[4/6] Required files check\n'
required_files=(
  "Aura/AuraApp.swift"
  "Aura/Info.plist"
  "Aura.xcodeproj/project.pbxproj"
  "docs/RELEASE_QA_CHECKLIST.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file"
    exit 1
  fi
  echo "ok: $file"
done

printf '\n[5/6] Commit head summary\n'
git --no-pager log --oneline -n 5

printf '\n[6/6] Release smoke completed successfully\n'
