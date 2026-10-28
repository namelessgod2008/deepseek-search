#!/usr/bin/env python3
"""Search the web with the DeepSeek Search API and print JSON.

使用 DeepSeek Search API 检索网页并输出 JSON。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


# DeepSeek Search API endpoint / DeepSeek 搜索 API 端点
API_URL = "https://api.deepseek.com/v1/tools/search"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Call the DeepSeek Search API / 调用 DeepSeek 搜索 API"
    )
    parser.add_argument(
        "query",
        help="Search query, 1-128 Unicode characters / 搜索词，1 至 128 个 Unicode 字符",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=10,
        help="Number of results, 1-50 / 结果数，1 至 50",
    )
    parser.add_argument(
        "--ori-question",
        help="Original question that triggered the search / 触发搜索的原始问题",
    )
    parser.add_argument(
        "--localization",
        help="Optional IP address for localized results / 用于本地化搜索结果的可选 IP 地址",
    )
    parser.add_argument(
        "--need-content",
        action="store_true",
        help="Request page bodies in addition to summaries and snippets / 在摘要和片段之外请求网页正文",
    )
    parser.add_argument(
        "--api-key-file",
        type=Path,
        help="File containing the DeepSeek API key / 包含 DeepSeek API Key 的文件",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
        help="Request timeout in seconds / 请求超时秒数",
    )
    return parser.parse_args()


def read_key_file(path: Path) -> str:
    try:
        key = path.expanduser().read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise ValueError(f"Cannot read API key file / 无法读取 API Key 文件 {path}: {exc}") from exc
    if not key:
        raise ValueError(f"API key file is empty / API Key 文件为空: {path}")
    if "\n" in key or "\r" in key:
        raise ValueError(f"API key file must contain one line / API Key 文件必须只包含一行: {path}")
    return key


def resolve_api_key(api_key_file: Path | None) -> str:
    # Resolve credentials without exposing them in logs / 解析凭据且不在日志中暴露凭据
    direct_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if direct_key:
        return direct_key

    configured_file = os.environ.get("DEEPSEEK_API_KEY_FILE", "").strip()
    candidates: list[Path] = []
    if api_key_file is not None:
        candidates.append(api_key_file)
    if configured_file:
        candidates.append(Path(configured_file))
    candidates.extend(
        [
            Path.home() / ".config" / "deepseek" / "api_key",
            Path.cwd() / ".deepseek_api_key",
        ]
    )

    for path in candidates:
        if path.expanduser().is_file():
            return read_key_file(path)

    searched = ", ".join(str(path) for path in candidates)
    raise ValueError(
        "DeepSeek API key not found. Set DEEPSEEK_API_KEY or DEEPSEEK_API_KEY_FILE, "
        "or pass --api-key-file. / 未找到 DeepSeek API Key。请设置 DEEPSEEK_API_KEY 或 "
        f"DEEPSEEK_API_KEY_FILE，或提供 --api-key-file。已检查: {searched}"
    )


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    # Validate API constraints before network access / 联网前校验 API 限制
    query = args.query.strip()
    if not 1 <= len(query) <= 128:
        raise ValueError(
            "query must contain 1-128 Unicode characters / query 必须包含 1 至 128 个 Unicode 字符"
        )
    if not 1 <= args.count <= 50:
        raise ValueError("--count must be between 1 and 50 / --count 必须在 1 至 50 之间")

    payload: dict[str, Any] = {"query": query, "count": args.count}
    if args.ori_question is not None:
        original_question = args.ori_question.strip()
        if not 1 <= len(original_question) <= 128:
            raise ValueError(
                "--ori-question must contain 1-128 Unicode characters / "
                "--ori-question 必须包含 1 至 128 个 Unicode 字符"
            )
        payload["ori_question"] = original_question
    if args.localization is not None:
        payload["localization"] = args.localization
    if args.need_content:
        payload["need_content"] = True
    return payload


def api_error_message(exc: urllib.error.HTTPError) -> str:
    try:
        raw_body = exc.read().decode("utf-8", errors="replace")
        payload = json.loads(raw_body)
        message = payload.get("error", {}).get("message")
        if isinstance(message, str) and message:
            return f"HTTP {exc.code}: {message}"
        return f"HTTP {exc.code}: {raw_body[:1000]}"
    except (OSError, ValueError, json.JSONDecodeError):
        return f"HTTP {exc.code}: {exc.reason}"


def search(payload: dict[str, Any], api_key: str, timeout: float) -> Any:
    # Send a JSON POST request / 发送 JSON POST 请求
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "codex-deepseek-search/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(api_error_message(exc)) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        reason = getattr(exc, "reason", exc)
        raise RuntimeError(f"Network request failed / 网络请求失败: {reason}") from exc

    try:
        return json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("DeepSeek returned non-JSON content / DeepSeek 返回了非 JSON 内容") from exc


def main() -> int:
    # Use distinct exit codes for configuration and API failures / 用不同退出码区分配置错误与 API 失败
    args = parse_args()
    try:
        payload = build_payload(args)
        api_key = resolve_api_key(args.api_key_file)
        result = search(payload, api_key, args.timeout)
    except ValueError as exc:
        print(f"Configuration error / 配置错误: {exc}", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(f"Search failed / 搜索失败: {exc}", file=sys.stderr)
        return 1

    # Emit machine-readable JSON / 输出机器可读 JSON
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
