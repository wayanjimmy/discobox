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

settings="$HOME/.config/discobox/dsh-harness.json"
case "$model" in
judge) model=$(jq -r '.judgeModel // .defaultModel // ""' "$settings") ;;
fast) model=$(jq -r '.fastModel // .defaultModel // ""' "$settings") ;;
"") model=$(jq -r '.defaultModel // ""' "$settings") ;;
esac
if [ -n "$system" ]; then prompt=$(printf '%s\n\n%s\n' "$system" "$prompt"); fi
if [ -n "$schema" ]; then
	prompt=$(printf '%s\n\nReply with one JSON document and nothing else. It must validate against this JSON Schema:\n%s\n' "$prompt" "$schema")
fi

# The generated overlay chooses the normal default. A temporary overlay lets
# the one-shot role select another configured model without mutating DSH_HOME.
patch=$(mktemp)
trap 'rm -f "$patch"' EXIT HUP INT TERM
model_json=$(printf '%s' "$model" | jq -Rs .)
cat >"$patch" <<EOF
- id: agent-default-model
  name: '@deepseek-ai/dsh-agent-default-model'
  config:
    provider: cpa
    model: $model_json
EOF
if [ -n "$no_tools" ]; then
	for id in tool-bash tool-pwsh tool-jobs tool-fs tool-fs-search tool-skill \
		tool-subagent-control tool-subagent-list-agents tool-subagent \
		tool-subagent-fork tool-workflow tool-todo tool-goal tool-ralph tool-web; do
		printf '%s\n' "- id: $id" "  disabled: true" >>"$patch"
	done
fi
dsh --profile headless --patch "$patch" "$prompt"
