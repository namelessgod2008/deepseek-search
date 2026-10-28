#!/usr/bin/env node
/**
 * Fetch a web page with the DeepSeek Fetch API and print JSON.
 * 使用 DeepSeek Fetch API 获取网页并输出 JSON。
 *
 * Requires Node.js 18 or newer (global fetch).
 * 需要 Node.js 18 或更高版本（提供全局 fetch）。
 */

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// DeepSeek Fetch API endpoint / DeepSeek 网页获取 API 端点
const API_URL = "https://api.deepseek.com/v1/tools/fetch";
const HELP = `Usage: nodejs scripts/deepseek-fetch.js URL [options]
用法：nodejs scripts/deepseek-fetch.js URL [选项]

Options / 选项:
  --api-key-file FILE       File containing the DeepSeek API key / 包含 DeepSeek API Key 的文件
  --timeout SECONDS         Request timeout, default 60 / 请求超时秒数，默认 60
  -h, --help                Show this help / 显示此帮助`;

function failConfiguration(message) {
  // Configuration errors use exit code 2 / 配置错误使用退出码 2
  console.error(`Configuration error / 配置错误: ${message}`);
  process.exit(2);
}

function failFetch(message) {
  // Network and API errors use exit code 1 / 网络和 API 错误使用退出码 1
  console.error(`Fetch failed / 网页获取失败: ${message}`);
  process.exit(1);
}

function requireValue(args, index, option) {
  if (index + 1 >= args.length) {
    failConfiguration(`${option} requires a value / ${option} 需要一个值`);
  }
  return args[index + 1];
}

function parseArgs(argv) {
  const options = {
    targetUrl: null,
    apiKeyFile: null,
    timeout: 60,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "-h" || arg === "--help") {
      console.log(HELP);
      process.exit(0);
    }
    if (arg === "--api-key-file") {
      options.apiKeyFile = requireValue(argv, index, arg);
      index += 1;
      continue;
    }
    if (arg === "--timeout") {
      options.timeout = Number(requireValue(argv, index, arg));
      index += 1;
      continue;
    }
    if (arg.startsWith("-")) {
      failConfiguration(`unknown option / 未知选项: ${arg}`);
    }
    if (options.targetUrl !== null) {
      failConfiguration("only one URL is allowed / 只允许一个 URL");
    }
    options.targetUrl = arg;
  }

  if (options.targetUrl === null) {
    failConfiguration("url is required / 必须提供 URL");
  }
  return options;
}

function readKeyFile(file) {
  const expanded = file.startsWith("~/")
    ? path.join(os.homedir(), file.slice(2))
    : file;
  let key;
  try {
    key = fs.readFileSync(expanded, "utf8").trim();
  } catch (error) {
    throw new Error(`Cannot read API key file / 无法读取 API Key 文件 ${file}: ${error.message}`);
  }
  if (!key) {
    throw new Error(`API key file is empty / API Key 文件为空: ${file}`);
  }
  if (/[\r\n]/.test(key)) {
    throw new Error(`API key file must contain one line / API Key 文件必须只包含一行: ${file}`);
  }
  return key;
}

function resolveApiKey(apiKeyFile) {
  // Resolve credentials without exposing them in output / 解析凭据且不在输出中暴露凭据
  const directKey = (process.env.DEEPSEEK_API_KEY || "").trim();
  if (directKey) {
    return directKey;
  }

  const candidates = [];
  if (apiKeyFile) {
    candidates.push(apiKeyFile);
  }
  if ((process.env.DEEPSEEK_API_KEY_FILE || "").trim()) {
    candidates.push(process.env.DEEPSEEK_API_KEY_FILE.trim());
  }
  candidates.push(path.join(os.homedir(), ".config", "deepseek", "api_key"));
  candidates.push(path.join(process.cwd(), ".deepseek_api_key"));

  for (const candidate of candidates) {
    const expanded = candidate.startsWith("~/")
      ? path.join(os.homedir(), candidate.slice(2))
      : candidate;
    if (fs.existsSync(expanded) && fs.statSync(expanded).isFile()) {
      return readKeyFile(candidate);
    }
  }

  throw new Error(
    "DeepSeek API key not found. Set DEEPSEEK_API_KEY or DEEPSEEK_API_KEY_FILE, "
      + "or pass --api-key-file. / 未找到 DeepSeek API Key。请设置 DEEPSEEK_API_KEY 或 "
      + `DEEPSEEK_API_KEY_FILE，或提供 --api-key-file。已检查: ${candidates.join(", ")}`,
  );
}

function buildPayload(options) {
  // Validate the target URL before network access / 联网前校验目标 URL
  const targetUrl = options.targetUrl.trim();
  if ([...targetUrl].length < 1 || [...targetUrl].length > 8192) {
    throw new Error(
      "url must contain 1-8192 Unicode characters / url 必须包含 1 至 8192 个 Unicode 字符",
    );
  }
  if (/[\s\u0000-\u001f\u007f]/u.test(targetUrl)) {
    throw new Error("url must not contain whitespace or control characters / url 不能包含空白或控制字符");
  }
  if (!/^https?:\/\//iu.test(targetUrl)) {
    throw new Error("url must be an HTTP or HTTPS URL with a host / url 必须是包含主机名的 HTTP 或 HTTPS URL");
  }
  const authority = targetUrl.match(/^https?:\/\/([^/?#]*)/iu)?.[1] || "";
  if (!authority) {
    throw new Error("url must be an HTTP or HTTPS URL with a host / url 必须是包含主机名的 HTTP 或 HTTPS URL");
  }
  if (authority.includes("@")) {
    throw new Error("url must not contain a username or password / url 不能包含用户名或密码");
  }

  let parsed;
  try {
    parsed = new URL(targetUrl);
  } catch (error) {
    throw new Error(`url is not a valid HTTP or HTTPS URL / url 不是有效的 HTTP 或 HTTPS URL: ${error.message}`);
  }
  if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) {
    throw new Error("url must be an HTTP or HTTPS URL with a host / url 必须是包含主机名的 HTTP 或 HTTPS URL");
  }
  if (!Number.isFinite(options.timeout) || options.timeout <= 0) {
    throw new Error("--timeout must be greater than zero / --timeout 必须大于零");
  }

  return { url: targetUrl };
}

async function fetchPage(payload, apiKey, timeout) {
  // Send a JSON POST request / 发送 JSON POST 请求
  let response;
  try {
    response = await fetch(API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        "User-Agent": "codex-deepseek-fetch/1.0",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeout * 1000),
    });
  } catch (error) {
    throw new Error(`Network request failed / 网络请求失败: ${error.message}`);
  }

  const rawBody = await response.text();
  if (!response.ok) {
    let message = rawBody.slice(0, 1000);
    try {
      const parsed = JSON.parse(rawBody);
      if (typeof parsed?.error?.message === "string" && parsed.error.message) {
        message = parsed.error.message;
      }
    } catch {
      // Preserve the raw response prefix when the error body is not JSON.
      // 当错误响应不是 JSON 时，保留原始响应的前一部分。
    }
    throw new Error(`HTTP ${response.status}: ${message}`);
  }

  let result;
  try {
    result = JSON.parse(rawBody);
  } catch {
    throw new Error("DeepSeek returned non-JSON content / DeepSeek 返回了非 JSON 内容");
  }
  if (typeof result?.title !== "string" || typeof result?.content !== "string") {
    throw new Error("DeepSeek returned an invalid fetch response / DeepSeek 返回了无效的网页获取响应");
  }
  return result;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  let payload;
  let apiKey;
  try {
    payload = buildPayload(options);
    apiKey = resolveApiKey(options.apiKeyFile);
  } catch (error) {
    failConfiguration(error.message);
  }

  let result;
  try {
    result = await fetchPage(payload, apiKey, options.timeout);
  } catch (error) {
    failFetch(error.message);
  }

  // Emit machine-readable JSON / 输出机器可读 JSON
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => failFetch(error.message));
