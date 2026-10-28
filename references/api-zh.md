[English](api.md) | [简体中文](api-zh.md)

# DeepSeek Search API 参考

## 请求

```text
POST https://api.deepseek.com/v1/tools/search
Authorization: Bearer <DEEPSEEK_API_KEY>
Content-Type: application/json
Accept: application/json
```

`Accept` 请求头可选，用于明确请求 JSON 格式的响应。

任何具备 HTTPS 和 JSON 能力的客户端都可调用该端点。该 skill 内置 Python、Node.js 以及带 curl 的 Bash 实现；Bash 本身不提供 HTTPS 或 JSON 处理能力。GNU wget、Ruby、Perl、Java 和 Go 也能实现该请求，但不属于此 skill 的支持范围。

请求字段：

- `query`：必填字符串，包含 1 至 128 个 Unicode 字符，不能只包含空白字符；支持 `site:`、`-site:` 和引号短语等运算符。
- `count`：可选整数，范围为 1 至 50，默认 10。
- `ori_question`：可选原始问题，包含 1 至 128 个 Unicode 字符，可帮助接口理解查询；`null` 视为未提供。
- `localization`：可选字符串，内容为用于本地化搜索结果的 IP 地址；默认空字符串。
- `need_content`：可选布尔值，默认 false；为 true 时请求网页正文，为 false 时 `content` 固定为空字符串。

## 响应

成功响应包含必填的 `results` 数组；查询没有匹配结果时该数组为空。每条结果包含以下字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `rerank_score` | 浮点数 | 相关性、权威性和时效性的综合分数，范围为 0 至 3；1.5 及以上通常属于高质量结果。 |
| `title` | 字符串 | 结果标题。 |
| `url` | 字符串 | 来源 URL。 |
| `snippet` | 字符串 | 与查询相关的简短摘要，通常为 100 至 200 个字符，供界面展示。 |
| `summary` | 字符串 | 与查询相关的较长摘要，通常为 600 至 800 个字符，供模型阅读。 |
| `content` | 字符串 | 网页正文；`need_content` 为 false 或正文不可用时为空字符串。 |
| `site_name` | 字符串或 null | 站点名称；不可用时为 `null`。 |
| `site_icon` | 字符串或 null | 站点图标 URL；不可用时为 `null`。 |
| `date` | RFC 3339 UTC 日期时间或 null | 发布时间；无法确定时为 `null`。 |
| `authority` | 整数 | 权威性等级，范围为 -1 至 4；-1 表示未知，3 及以上表示高权威来源。 |

`snippet` 和 `summary` 的长度是常见范围，不是严格的响应约束。可选结果元数据缺失时使用 `null` 表示，而不是省略字段。

## 查询运算符

- `site:example.com` 限定站点；多个站点可用 `OR site:` 组合。
- `-site:example.com` 排除站点。
- `"exact phrase"` 匹配精确短语。
- `-term` 或 `-"exact phrase"` 排除词语或短语。
- `lang:zh,en` 限定语言代码。
- `after:2025`、`after:2025-01-01` 限定发布日期下限。
- `before:2026`、`before:2026-06-01` 限定发布日期上限。

## 错误处理

- `400`：请求头、JSON 或字段值无效；修正请求。
- `401`：Key 缺失或无效；检查凭据。
- `402`：账户余额不足；不要盲目重试。
- `408`、`429`、`500`、`504`：短暂故障或限流；可进行有限次退避重试。
- 其他 `4xx`：先修正请求再重试。

空 `results` 数组是正常响应，不表示 API 故障。

官方文档：<https://api-docs.deepseek.com/guides/search>
