#!/usr/bin/env python3
"""Fetch a web page with the DeepSeek Fetch API and print JSON.

使用 DeepSeek Fetch API 获取网页并输出 JSON。
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


# DeepSeek Fetch API endpoint / DeepSeek 网页获取 API 端点
API_URL = "https://api.deepseek.com/v1/tools/fetch"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch a web page as JSON via the DeepSeek Fetch API / "
        "通过 DeepSeek Fetch API 获取网页并输出 JSON"
    )
    parser.add_argument(
        "url",
        help="HTTP or HTTPS URL, 1-8192 Unicode characters / HTTP 或 HTTPS URL，1 至 8192 个 Unicode 字符",
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


def build_payload(args: argparse.Namespace) -> dict[str, str]:
    # Validate the target URL before network access / 联网前校验目标 URL
    target_url = args.url.strip()
    if not 1 <= len(target_url) <= 8192:
        raise ValueError(
            "url must contain 1-8192 Unicode characters / url 必须包含 1 至 8192 个 Unicode 字符"
        )
    if any(character.isspace() or ord(character) < 32 for character in target_url):
        raise ValueError("url must not contain whitespace or control characters / url 不能包含空白或控制字符")

    try:
        parsed = urlsplit(target_url)
        # Accessing port validates a numeric port when one is present.
        # 访问 port 属性可校验存在端口时其格式是否有效。
        _ = parsed.port
    except ValueError as exc:
        raise ValueError(f"url is not a valid HTTP or HTTPS URL / url 不是有效的 HTTP 或 HTTPS URL: {exc}") from exc

    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ValueError("url must be an HTTP or HTTPS URL with a host / url 必须是包含主机名的 HTTP 或 HTTPS URL")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("url must not contain a username or password / url 不能包含用户名或密码")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        raise ValueError("--timeout must be greater than zero / --timeout 必须大于零")

    return {"url": target_url}


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


def fetch_page(payload: dict[str, str], api_key: str, timeout: float) -> dict[str, str]:
    # Send a JSON POST request / 发送 JSON POST 请求
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "codex-deepseek-fetch/1.0",
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
        result = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("DeepSeek returned non-JSON content / DeepSeek 返回了非 JSON 内容") from exc
    if (
        not isinstance(result, dict)
        or not isinstance(result.get("title"), str)
        or not isinstance(result.get("content"), str)
    ):
        raise RuntimeError("DeepSeek returned an invalid fetch response / DeepSeek 返回了无效的网页获取响应")
    return result


def main() -> int:
    # Use distinct exit codes for configuration and API failures / 用不同退出码区分配置错误与 API 失败
    args = parse_args()
    try:
        payload = build_payload(args)
        api_key = resolve_api_key(args.api_key_file)
    except ValueError as exc:
        print(f"Configuration error / 配置错误: {exc}", file=sys.stderr)
        return 2

    try:
        result = fetch_page(payload, api_key, args.timeout)
    except RuntimeError as exc:
        print(f"Fetch failed / 网页获取失败: {exc}", file=sys.stderr)
        return 1

    # Emit machine-readable JSON / 输出机器可读 JSON
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
