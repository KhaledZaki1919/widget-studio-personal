#!/usr/bin/env bash
# Fails if a tracked file contains something that looks like a real secret (ADR-007).
# Runs as the pre-push hook (.githooks/pre-push) and as the first CI step. The repo is public.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PATTERN='sk-ant-[A-Za-z0-9_-]{20,}|sk-or-v1-[A-Za-z0-9]{20,}|sk-(proj-)?[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|AQ\.[A-Za-z0-9_-]{30,}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|nvapi-[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{40,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

hits="$(git ls-files -z | grep -zv '^scripts/secret-scan.sh$' | xargs -0 grep -nIE "$PATTERN" -- 2>/dev/null || true)"
if [ -n "$hits" ]; then
  echo "Secret scan failed. Possible secrets (file:line):" >&2
  cut -d: -f1,2 <<<"$hits" >&2
  exit 1
fi
echo "Secret scan passed ($(git ls-files | wc -l | tr -d ' ') tracked files)."
