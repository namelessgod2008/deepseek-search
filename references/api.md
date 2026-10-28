[English](api.md) | [简体中文](api-zh.md)

# DeepSeek Search API Reference

## Request

```text
POST https://api.deepseek.com/v1/tools/search
Authorization: Bearer <DEEPSEEK_API_KEY>
Content-Type: application/json
```

Request fields:

- `query`: required string containing 1 to 128 Unicode characters. Whitespace-only queries are invalid.
- `count`: optional integer from 1 to 50; defaults to 10.
- `ori_question`: optional original question containing 1 to 128 characters.
- `localization`: optional IP address used to localize results.
- `need_content`: optional boolean; defaults to false. When true, request page bodies.

A successful response contains a `results` array. Each result commonly includes:

- `rerank_score`: a combined relevance, authority, and freshness score.
- `title`, `url`, `snippet`, `summary`: title, source URL, and summaries.
- `content`: page body. It is empty when `need_content` is false or content is unavailable.
- `site_name`, `site_icon`, `date`, `authority`: site and freshness metadata.

## Query Operators

- `site:example.com` restricts results to a site. Combine sites with `OR site:`.
- `-site:example.com` excludes a site.
- `"exact phrase"` matches an exact phrase.
- `-term` or `-"exact phrase"` excludes a term or phrase.
- `lang:zh,en` restricts language codes.
- `after:2025` and `after:2025-01-01` set an inclusive publication-date lower bound.
- `before:2026` and `before:2026-06-01` set an exclusive publication-date upper bound.

## Error Handling

- `400`: invalid headers, JSON, or field values; correct the request.
- `401`: missing or invalid key; check credentials.
- `402`: insufficient account balance; do not retry blindly.
- `408`, `429`, `500`, and `504`: transient failure or rate limiting; bounded backoff retry is appropriate.
- Other `4xx`: correct the request before retrying.

An empty `results` array is a normal response and does not indicate an API failure.

Official documentation: <https://api-docs.deepseek.com/guides/search>
