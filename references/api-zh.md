[English](api.md) | [简体中文](api-zh.md)

# DeepSeek Search API 参考

## 请求

```text
POST https://api.deepseek.com/v1/tools/search
Authorization: Bearer <DEEPSEEK_API_KEY>
Content-Type: application/json
```

请求字段：

- `query`：必填字符串，包含 1 至 128 个 Unicode 字符，不能只包含空白字符。
- `count`：可选整数，范围为 1 至 50，默认 10。
- `ori_question`：可选原始问题，包含 1 至 128 个字符。
- `localization`：可选 IP 地址，用于本地化搜索结果。
- `need_content`：可选布尔值，默认 false；为 true 时请求网页正文。

成功的响应包含 `results` 数组。每条结果通常包括：

- `rerank_score`：相关性、权威性和时效性的综合分数。
- `title`、`url`、`snippet`、`summary`：标题、原始链接和摘要。
- `content`：网页正文；`need_content` 为 false 或正文不可用时为空。
- `site_name`、`site_icon`、`date`、`authority`：站点和时效元数据。

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
