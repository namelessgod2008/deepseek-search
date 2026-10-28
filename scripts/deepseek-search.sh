#!/usr/bin/env bash
# Search the web with curl and the DeepSeek Search API, then print JSON.
# 使用 curl 调用 DeepSeek Search API 检索网页并输出 JSON。
#
# Requires Bash, curl, and jq. The API key is sent to curl through standard
# input, so it does not appear in the process argument list.
# 需要 Bash、curl 和 jq。API Key 通过标准输入传给 curl，不会出现在进程参数列表中。

set -uo pipefail
umask 077

# DeepSeek Search API endpoint / DeepSeek 搜索 API 端点
API_URL="https://api.deepseek.com/v1/tools/search"

print_help() {
  cat <<'HELP'
Usage: bash scripts/deepseek-search.sh QUERY [options]
用法：bash scripts/deepseek-search.sh 查询词 [选项]

Options / 选项:
  --count N                 Number of results, 1-50 / 结果数，1 至 50
  --ori-question TEXT       Original question that triggered the search / 触发搜索的原始问题
  --localization IP         Optional IP address for localized results / 用于本地化搜索结果的可选 IP 地址
  --need-content            Request page bodies / 请求网页正文
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

search_error() {
  # Network and API errors use exit code 1 / 网络和 API 错误使用退出码 1
  printf 'Search failed / 搜索失败: %s\n' "$1" >&2
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

query=""
count="10"
ori_question=""
has_ori_question=0
localization=""
has_localization=0
need_content=0
api_key_file=""
timeout="60"

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --need-content)
      need_content=1
      shift
      ;;
    --count|--ori-question|--localization|--api-key-file|--timeout)
      option="$1"
      (( $# >= 2 )) || config_error "$option requires a value / $option 需要一个值"
      case "$option" in
        --count) count="$2" ;;
        --ori-question) ori_question="$2"; has_ori_question=1 ;;
        --localization) localization="$2"; has_localization=1 ;;
        --api-key-file) api_key_file="$2" ;;
        --timeout) timeout="$2" ;;
      esac
      shift 2
      ;;
    -*)
      config_error "unknown option / 未知选项: $1"
      ;;
    *)
      [[ -z "$query" ]] || config_error "only one query is allowed / 只允许一个查询词"
      query="$1"
      shift
      ;;
  esac
done

[[ -n "$query" ]] || config_error "query is required / 必须提供查询词"
command -v curl >/dev/null 2>&1 || config_error "curl is required / 需要 curl"
command -v jq >/dev/null 2>&1 || config_error "jq is required by the curl backend / curl 后端需要 jq"
[[ "$-" != *x* ]] || config_error "disable shell tracing before using credentials / 使用凭据前必须关闭 shell 跟踪"

query="$(trim "$query")"
query_length="$(jq -Rn --arg value "$query" '$value | length')"
(( query_length >= 1 && query_length <= 128 )) || \
  config_error "query must contain 1-128 Unicode characters / query 必须包含 1 至 128 个 Unicode 字符"

[[ "$count" =~ ^[0-9]+$ ]] || config_error "--count must be an integer / --count 必须是整数"
count=$((10#$count))
(( count >= 1 && count <= 50 )) || \
  config_error "--count must be between 1 and 50 / --count 必须在 1 至 50 之间"

[[ "$timeout" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] || \
  config_error "--timeout must be greater than zero / --timeout 必须大于零"
jq -en --arg value "$timeout" '($value | tonumber) > 0' >/dev/null 2>&1 || \
  config_error "--timeout must be greater than zero / --timeout 必须大于零"

if (( has_ori_question )); then
  ori_question="$(trim "$ori_question")"
  question_length="$(jq -Rn --arg value "$ori_question" '$value | length')"
  (( question_length >= 1 && question_length <= 128 )) || \
    config_error "--ori-question must contain 1-128 Unicode characters / --ori-question 必须包含 1 至 128 个 Unicode 字符"
fi

resolve_api_key "$api_key_file"
[[ -n "$api_key" ]] || config_error "DeepSeek API key is empty / DeepSeek API Key 为空"

payload_file="$(mktemp)"
body_file="$(mktemp)"
error_file="$(mktemp)"
trap 'rm -f "$payload_file" "$body_file" "$error_file"' EXIT
chmod 600 "$payload_file" "$body_file" "$error_file"

jq -n \
  --arg query "$query" \
  --argjson count "$count" \
  --arg ori_question "$ori_question" \
  --arg localization "$localization" \
  --argjson has_ori_question "$has_ori_question" \
  --argjson has_localization "$has_localization" \
  --argjson need_content "$need_content" '
    {query: $query, count: $count}
    + (if $has_ori_question == 1 then {ori_question: $ori_question} else {} end)
    + (if $has_localization == 1 then {localization: $localization} else {} end)
    + (if $need_content == 1 then {need_content: true} else {} end)
  ' >"$payload_file" || config_error "cannot build JSON request / 无法构造 JSON 请求"

# Quote the Authorization value as a curl config string. The key travels on
# standard input rather than in curl's command arguments.
# 将 Authorization 值转换为 curl 配置字符串；密钥通过标准输入传输，不放入 curl 命令行参数。
header_json="$(printf 'Authorization: Bearer %s' "$api_key" | jq -Rs .)"

http_code="$(
  printf 'header = %s\n' "$header_json" | curl --config - \
    --request POST \
    --url "$API_URL" \
    --header 'Content-Type: application/json' \
    --header 'User-Agent: codex-deepseek-search/1.0' \
    --data-binary "@$payload_file" \
    --max-time "$timeout" \
    --silent \
    --show-error \
    --output "$body_file" \
    --write-out '%{http_code}' \
    2>"$error_file"
)" || {
  detail="$(<"$error_file")"
  search_error "Network request failed / 网络请求失败: ${detail:-curl exited with an error}"
}

if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
  detail="$(jq -r '.error.message // empty' "$body_file" 2>/dev/null || true)"
  [[ -n "$detail" ]] || detail="$(head -c 1000 "$body_file" 2>/dev/null || true)"
  search_error "HTTP ${http_code}: ${detail:-unknown error / 未知错误}"
fi

jq . "$body_file" >/dev/null 2>&1 || \
  search_error "DeepSeek returned non-JSON content / DeepSeek 返回了非 JSON 内容"
cat "$body_file"
printf '\n'
