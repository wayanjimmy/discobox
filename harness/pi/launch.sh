#!/bin/sh
set -eu

SETTINGS="$HOME/.config/discobox/pi-harness.json"
model=$(jq -r '.defaultModel // ""' "$SETTINGS" 2>/dev/null || true)

if [ "${1-}" = "--resume" ]; then
	set -- --continue
elif [ "$#" -gt 0 ]; then
	prompt="$1"
	shift
	for word in "$@"; do prompt="$prompt $word"; done
	set -- "$prompt"
fi

if [ -n "$model" ]; then
	set -- --model "cpa/$model" "$@"
fi
exec pi "$@"
