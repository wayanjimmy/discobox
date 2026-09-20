#!/bin/sh
set -eu

model=""
system=""
prompt=""
schema=""
no_tools=""
while [ $# -gt 0 ]; do
	case "$1" in
	--model) model="${2:-}"; shift 2 ;;
	--model=*) model="${1#--model=}"; shift ;;
	--system) system="${2:-}"; shift 2 ;;
	--system=*) system="${1#--system=}"; shift ;;
	--prompt) prompt="${2:-}"; shift 2 ;;
	--prompt=*) prompt="${1#--prompt=}"; shift ;;
	--output-schema) schema="${2:-}"; shift 2 ;;
	--output-schema=*) schema="${1#--output-schema=}"; shift ;;
	--no-tools) no_tools=1; shift ;;
	--) shift; break ;;
	-*) echo "discobox-prompt: unknown flag $1" >&2; exit 2 ;;
	*) break ;;
	esac
done
[ -n "$prompt" ] || prompt="$*"
[ -n "$prompt" ] || { echo "discobox-prompt: no prompt given" >&2; exit 2; }

settings="$HOME/.config/discobox/pi-harness.json"
case "$model" in
judge) model=$(jq -r '.judgeModel // .defaultModel // ""' "$settings") ;;
fast) model=$(jq -r '.fastModel // .defaultModel // ""' "$settings") ;;
"") model=$(jq -r '.defaultModel // ""' "$settings") ;;
esac

if [ -n "$schema" ]; then
	prompt=$(printf '%s\n\nReply with one JSON document and nothing else. It must validate against this JSON Schema:\n%s\n' "$prompt" "$schema")
fi
set -- pi -p --no-session --model "cpa/$model"
[ -z "$system" ] || set -- "$@" --append-system-prompt "$system"
if [ -n "$no_tools" ]; then
	set -- "$@" --no-tools --no-extensions --no-skills --no-prompt-templates --no-themes --no-context-files --no-approve
fi
exec "$@" "$prompt"
