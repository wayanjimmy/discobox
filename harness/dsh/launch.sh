#!/bin/sh
set -eu

if [ "${1-}" = "--resume" ]; then set --; fi
if [ "$#" -gt 0 ]; then
	echo "DeepSeek Harness opens in the browser; submit this initial task there:" >&2
	printf '  %s\n' "$*" >&2
fi
exec dsh web --host 127.0.0.1 --port 3080 --no-open
