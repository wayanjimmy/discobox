#!/bin/sh
set -eu

OUTPUT=/run/discobox/configure/harness-configure.json
HOST=cli-proxy.jimboylabs.biz.id
BASE_URL=https://cli-proxy.jimboylabs.biz.id/v1
WORK=$(mktemp -d)
saved_stty=""
cleanup() {
	[ -z "$saved_stty" ] || stty "$saved_stty" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

ask_yes_no() {
	printf '%s [Y/n] ' "$1" >&2
	IFS= read -r answer
	case "$answer" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}
read_secret() {
	label=$1
	printf '%s: ' "$label" >&2
	saved_stty=$(stty -g)
	stty -echo
	IFS= read -r value
	stty "$saved_stty"
	saved_stty=""
	printf '\n' >&2
	[ -n "$value" ] || { echo "$label cannot be empty" >&2; exit 1; }
	printf '%s' "$value"
}

reuse=""
if [ -n "${PREV_CLI_PROXY_API_KEY:-}" ] && [ -n "${PREV_CF_ACCESS_CLIENT_ID:-}" ] && [ -n "${PREV_CF_ACCESS_CLIENT_SECRET:-}" ]; then
	if ask_yes_no "Keep the existing CLI Proxy API credentials?"; then reuse=1; fi
fi
if [ -n "$reuse" ]; then
	api_key=$PREV_CLI_PROXY_API_KEY
	client_id=$PREV_CF_ACCESS_CLIENT_ID
	client_secret=$PREV_CF_ACCESS_CLIENT_SECRET
else
	api_key=$(read_secret "CLI Proxy API key")
	client_id=$(read_secret "Cloudflare Access client ID")
	client_secret=$(read_secret "Cloudflare Access client secret")
fi

echo "Discovering models through CLI Proxy API..." >&2
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
	-H "Authorization: Bearer $api_key" \
	-H "CF-Access-Client-Id: $client_id" \
	-H "CF-Access-Client-Secret: $client_secret" \
	"$BASE_URL/models" >"$WORK/catalog.json"
jq -c '(.data // .models // []) | map(.slug // .id // .name // empty) | map(select(type == "string" and length > 0)) | unique' \
	"$WORK/catalog.json" >"$WORK/models.json"
[ "$(jq length "$WORK/models.json")" -gt 0 ] || { echo "CLI Proxy API returned no models" >&2; exit 1; }

select_model() {
	label=$1
	default=${2:-}
	echo "$label:" >&2
	jq -r 'to_entries[] | "  \(.key + 1)) \(.value)"' "$WORK/models.json" >&2
	if [ -n "$default" ]; then printf 'Selection [%s]: ' "$default" >&2; else printf 'Selection [1]: ' >&2; fi
	IFS= read -r choice
	[ -n "$choice" ] || choice=${default:-1}
	case "$choice" in *[!0-9]*|"") echo "Invalid selection" >&2; exit 1 ;; esac
	model=$(jq -r --argjson n "$choice" '.[$n - 1] // empty' "$WORK/models.json")
	[ -n "$model" ] || { echo "Invalid selection" >&2; exit 1; }
	printf '%s' "$model"
}

default_model=$(select_model "Default model")
default_index=$(jq -r --arg model "$default_model" 'index($model) + 1' "$WORK/models.json")
judge_model=$(select_model "Judge model" "$default_index")
fast_model=$(select_model "Fast model" "$default_index")
default_json=$(printf '%s' "$default_model" | jq -Rs .)
{
	cat <<EOF
- id: session-log-deepseek
  name: '@deepseek-ai/dsh-session-log-deepseek'
  disabled: true
- id: agent-default-model
  name: '@deepseek-ai/dsh-agent-default-model'
  config:
    provider: cpa
    model: $default_json
- id: llm-pi-ai
  name: '@deepseek-ai/dsh-llm-pi-ai'
  config:
    providers:
      cpa:
        displayName: CLI Proxy API
        apiKeyEnv: CLI_PROXY_API_KEY
        api: openai-responses
        baseURL: $BASE_URL
        headers:
          CF-Access-Client-Id: "{{ .secrets.CF_ACCESS_CLIENT_ID }}"
          CF-Access-Client-Secret: "{{ .secrets.CF_ACCESS_CLIENT_SECRET }}"
        models:
EOF
	jq -r '.[] | @json | "          - id: \(.)"' "$WORK/models.json"
} >"$WORK/cordis.patch.yml"

harness_settings=$(jq -c -n --arg default "$default_model" --arg judge "$judge_model" --arg fast "$fast_model" '{defaultModel:$default,judgeModel:$judge,fastModel:$fast}')
if [ -n "$reuse" ]; then
	secrets=$(jq -c -n --arg host "$HOST" '["CLI_PROXY_API_KEY","CF_ACCESS_CLIENT_ID","CF_ACCESS_CLIENT_SECRET"] | map({envName:.,name:.,type:"token",host:$host,usePrevious:true})')
else
	secrets=$(jq -c -n --arg host "$HOST" --arg api "$api_key" --arg id "$client_id" --arg secret "$client_secret" '[{envName:"CLI_PROXY_API_KEY",name:"CLI Proxy API key",type:"token",host:$host,value:{token:$api}},{envName:"CF_ACCESS_CLIENT_ID",name:"Cloudflare Access client ID",type:"token",host:$host,value:{token:$id}},{envName:"CF_ACCESS_CLIENT_SECRET",name:"Cloudflare Access client secret",type:"token",host:$host,value:{token:$secret}}]')
fi
jq -n --argjson secrets "$secrets" --rawfile patch "$WORK/cordis.patch.yml" --arg settings "$harness_settings" '{secrets:$secrets,files:[{path:".dsh/cordis.patch.yml",content:$patch,template:true},{path:".config/discobox/dsh-harness.json",content:$settings}]}' >"$OUTPUT"
echo "DeepSeek Harness configured with $(jq length "$WORK/models.json") CLI Proxy API models." >&2
