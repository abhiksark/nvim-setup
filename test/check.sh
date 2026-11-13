#!/bin/sh
# test/check.sh
# Checks the startup budget (median of 5 runs under 50 ms), then runs the headless
# checks in test/check.lua against the config that ~/.config/nvim points to.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for i in 1 2 3 4 5; do
  nvim --headless --startuptime "$tmp/st$i" +qa
  grep 'NVIM STARTED' "$tmp/st$i" | tail -n 1 | awk '{ print $1 }'
done | sort -n | sed -n 3p > "$tmp/median"
median=$(cat "$tmp/median")
if [ -n "$median" ] && awk -v m="$median" 'BEGIN { exit !(m + 0 < 50) }'; then
  echo "PASS startup: ${median} ms (budget 50)"
else
  echo "FAIL startup: ${median} ms (budget 50)"
  exit 1
fi

nvim --headless -c 'luafile test/check.lua'
