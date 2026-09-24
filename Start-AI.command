#!/bin/zsh
set -e
cd "${0:A:h}/backend"
if command -v bun >/dev/null 2>&1; then
  exec bun run dev
fi
exec "$HOME/.bun/bin/bun" run dev
