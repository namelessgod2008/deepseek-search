[English](api.md) | [简体中文](api-zh.md)

# DeepSeek Search API Reference

## Request

```text
POST https://api.deepseek.com/v1/tools/search
Authorization: Bearer <DEEPSEEK_API_KEY>
Content-Type: application/json
Accept: application/json
```

The `Accept` header is optional but explicitly requests a JSON response.

Any HTTPS and JSON capable client can call this endpoint. The skill bundles Python, Node.js, and Bash with curl implementations; Bash does not provide HTTPS or JSON handling by itself. GNU wget, Ruby, Perl, Java, and Go can also implement the request but are outside the skill's supported client set.

Request fields:

- `query`: required string containing 1 to 128 Unicode characters. Whitespace-only queries are invalid. Operators such as `site:`, `-site:`, and quoted phrases are supported.
- `count`: optional integer from 1 to 50; defaults to 10.
- `ori_question`: optional original question containing 1 to 128 Unicode characters. It can improve query understanding. `null` is treated as not provided.
- `localization`: optional string containing an IP address used to localize results; defaults to an empty string.
- `need_content`: optional boolean; defaults to false. When true, request page bodies. When false, `content` is always an empty string.

## Response

A successful response contains a required `results` array. It is empty when the query has no matches. Each result contains these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `rerank_score` | float | Combined relevance, authority, and freshness score from 0 to 3. Scores of 1.5 or higher are considered high quality. |
| `title` | string | Result title. |
| `url` | string | Source URL. |
| `snippet` | string | Short query-related summary, typically 100 to 200 characters, intended for UI display. |
| `summary` | string | Longer query-related summary, typically 600 to 800 characters, intended for model use. |
| `content` | string | Page body. Empty when `need_content` is false or content is unavailable. |
| `site_name` | string or null | Site name, or `null` when unavailable. |
| `site_icon` | string or null | Site icon URL, or `null` when unavailable. |
| `date` | RFC 3339 UTC date-time or null | Publication time, or `null` when unknown. |
| `authority` | integer | Authority tier from -1 to 4. `-1` means unknown; 3 or higher indicates a highly authoritative source. |

Field lengths in `snippet` and `summary` are typical values, not strict response constraints. Missing optional result metadata is represented by `null`, not by omitting the field.

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
