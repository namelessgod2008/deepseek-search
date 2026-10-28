#!/usr/bin/env bash
# Fetch a web page with curl and the DeepSeek Fetch API, then print JSON.
# 使用 curl 调用 DeepSeek Fetch API 获取网页并输出 JSON。
#
# Requires Bash, curl, and jq. The API key is sent to curl through standard
# input, so it does not appear in the process argument list.
# 需要 Bash、curl 和 jq。API Key 通过标准输入传给 curl，不会出现在进程参数列表中。

set -uo pipefail
umask 077

# DeepSeek Fetch API endpoint / DeepSeek 网页获取 API 端点
API_URL="https://api.deepseek.com/v1/tools/fetch"

print_help() {
  cat <<'HELP'
Usage: bash scripts/deepseek-fetch.sh URL [options]
用法：bash scripts/deepseek-fetch.sh URL [选项]

Options / 选项:
  --api-key-file FILE       File containing the DeepSeek API key / 包含 DeepSeek API Key 的文件
  --timeout SECONDS         Request timeout, default 60 / 请求超时秒数，默认 60
  -h, --help                Show this help / 显示此帮助
HELP
}

config_error() {
  # Configuration errors use exit code 2 / 配置错误使用退出码 2
  printf 'Configuration error / 配置错误: %s\n' "$1" >&2
  exit 2
}

fetch_error() {
  # Network and API errors use exit code 1 / 网络和 API 错误使用退出码 1
  printf 'Fetch failed / 网页获取失败: %s\n' "$1" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_key_file() {
  local file="$1"
  local expanded="${file/#\~/$HOME}"
  local key=""
  [[ -f "$expanded" ]] || return 1
  key="$(<"$expanded")"
  key="$(trim "$key")"
  [[ -n "$key" ]] || config_error "API key file is empty / API Key 文件为空: $file"
  if [[ "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
    config_error "API key file must contain one line / API Key 文件必须只包含一行: $file"
  fi
  api_key="$key"
}

resolve_api_key() {
  local explicit_file="${1:-}"
  local candidate
  local candidates=()

  api_key=""
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    api_key="$(trim "$DEEPSEEK_API_KEY")"
    return
  fi

  [[ -n "$explicit_file" ]] && candidates+=("$explicit_file")
  [[ -n "${DEEPSEEK_API_KEY_FILE:-}" ]] && candidates+=("$DEEPSEEK_API_KEY_FILE")
  candidates+=("$HOME/.config/deepseek/api_key" "$PWD/.deepseek_api_key")

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate/#\~/$HOME}" ]]; then
      read_key_file "$candidate"
      return
    fi
  done

  config_error \
    "DeepSeek API key not found. Set DEEPSEEK_API_KEY or DEEPSEEK_API_KEY_FILE, or pass --api-key-file. / 未找到 DeepSeek API Key。请设置 DEEPSEEK_API_KEY 或 DEEPSEEK_API_KEY_FILE，或提供 --api-key-file。已检查: ${candidates[*]}"
}

target_url=""
api_key_file=""
timeout="60"

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --api-key-file|--timeout)
      option="$1"
      (( $# >= 2 )) || config_error "$option requires a value / $option 需要一个值"
      case "$option" in
        --api-key-file) api_key_file="$2" ;;
        --timeout) timeout="$2" ;;
      esac
      shift 2
      ;;
    -*)
      config_error "unknown option / 未知选项: $1"
      ;;
    *)
      [[ -z "$target_url" ]] || config_error "only one URL is allowed / 只允许一个 URL"
      target_url="$1"
      shift
      ;;
  esac
done

[[ -n "$target_url" ]] || config_error "url is required / 必须提供 URL"
command -v curl >/dev/null 2>&1 || config_error "curl is required / 需要 curl"
command -v jq >/dev/null 2>&1 || config_error "jq is required by the curl backend / curl 后端需要 jq"
[[ "$-" != *x* ]] || config_error "disable shell tracing before using credentials / 使用凭据前必须关闭 shell 跟踪"

target_url="$(trim "$target_url")"
url_length="$(jq -Rn --arg value "$target_url" '$value | length')"
(( url_length >= 1 && url_length <= 8192 )) || \
  config_error "url must contain 1-8192 Unicode characters / url 必须包含 1 至 8192 个 Unicode 字符"
if [[ "$target_url" =~ [[:space:][:cntrl:]] ]]; then
  config_error "url must not contain whitespace or control characters / url 不能包含空白或控制字符"
fi

url_regex='^([Hh][Tt][Tt][Pp][Ss]?)://([^/?#]+)'
if [[ ! "$target_url" =~ $url_regex ]]; then
  config_error "url must be an HTTP or HTTPS URL with a host / url 必须是包含主机名的 HTTP 或 HTTPS URL"
fi
authority="${BASH_REMATCH[2]}"
[[ "$authority" != *@* ]] || \
  config_error "url must not contain a username or password / url 不能包含用户名或密码"

port=""
if [[ "$authority" == \[* ]]; then
  [[ "$authority" =~ ^\[[^]]+\](:[0-9]{1,5})?$ ]] || \
    config_error "url has an invalid host or port / url 的主机名或端口无效"
  after_host="${authority##*]}"
  [[ "$after_host" == :* ]] && port="${after_host#:}"
else
  [[ "$authority" =~ ^[^:]+(:[0-9]{1,5})?$ ]] || \
    config_error "url has an invalid host or port / url 的主机名或端口无效"
  [[ "$authority" == *:* ]] && port="${authority##*:}"
fi
if [[ -n "$port" ]]; then
  port_number=$((10#$port))
  (( port_number <= 65535 )) || \
    config_error "url has an invalid host or port / url 的主机名或端口无效"
fi

[[ "$timeout" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] || \
  config_error "--timeout must be greater than zero / --timeout 必须大于零"
jq -en --arg value "$timeout" '($value | tonumber) > 0' >/dev/null 2>&1 || \
  config_error "--timeout must be greater than zero / --timeout 必须大于零"

resolve_api_key "$api_key_file"
[[ -n "$api_key" ]] || config_error "DeepSeek API key is empty / DeepSeek API Key 为空"

payload_file="$(mktemp)"
body_file="$(mktemp)"
error_file="$(mktemp)"
trap 'rm -f "$payload_file" "$body_file" "$error_file"' EXIT
chmod 600 "$payload_file" "$body_file" "$error_file"

jq -n --arg url "$target_url" '{url: $url}' >"$payload_file" || \
  config_error "cannot build JSON request / 无法构造 JSON 请求"

# Quote the Authorization value as a curl config string. The key travels on
# standard input rather than in curl's command arguments.
# 将 Authorization 值转换为 curl 配置字符串；密钥通过标准输入传输，不放入 curl 的命令行参数。
header_json="$(printf 'Authorization: Bearer %s' "$api_key" | jq -Rs .)"

http_code="$(
  printf 'header = %s\n' "$header_json" | curl --config - \
    --request POST \
    --url "$API_URL" \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    --header 'User-Agent: codex-deepseek-fetch/1.0' \
    --data-binary "@$payload_file" \
    --max-time "$timeout" \
    --silent \
    --show-error \
    --output "$body_file" \
    --write-out '%{http_code}' \
    2>"$error_file"
)" || {
  detail="$(<"$error_file")"
  fetch_error "Network request failed / 网络请求失败: ${detail:-curl exited with an error}"
}

if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
  detail="$(jq -r '.error.message // empty' "$body_file" 2>/dev/null || true)"
  [[ -n "$detail" ]] || detail="$(head -c 1000 "$body_file" 2>/dev/null || true)"
  fetch_error "HTTP ${http_code}: ${detail:-unknown error / 未知错误}"
fi

jq -e 'type == "object" and (.title | type == "string") and (.content | type == "string")' \
  "$body_file" >/dev/null 2>&1 || \
  fetch_error "DeepSeek returned an invalid fetch response / DeepSeek 返回了无效的网页获取响应"

jq . "$body_file"
