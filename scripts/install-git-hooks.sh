#!/bin/sh
# Однократно после clone: подключить хуки из .githooks/
set -e
root="$(git rev-parse --show-toplevel)"
cd "$root"
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
echo "core.hooksPath=.githooks — хук commit-msg активен (удаление «Made-with: Cursor»)."
