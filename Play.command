#!/bin/zsh
set -e
cd "${0:A:h}"
exec node "$PWD/scripts/play.mjs"
