#!/usr/bin/env node
/**
 * Search the web with the DeepSeek Search API and print JSON.
 * 使用 DeepSeek Search API 检索网页并输出 JSON。
 *
 * Requires Node.js 18 or newer (global fetch).
 * 需要 Node.js 18 或更高版本（提供全局 fetch）。
 */

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// DeepSeek Search API endpoint / DeepSeek 搜索 API 端点
const API_URL = "https://api.deepseek.com/v1/tools/search";
const HELP = `Usage: nodejs scripts/deepseek-search.js QUERY [options]
用法：nodejs scripts/deepseek-search.js 查询词 [选项]

Options / 选项:
  --count N                 Number of results, 1-50 / 结果数，1 至 50
  --ori-question TEXT       Original question that triggered the search / 触发搜索的原始问题
  --localization IP         Optional IP address for localized results / 用于本地化搜索结果的可选 IP 地址
  --need-content            Request page bodies / 请求网页正文
  --api-key-file FILE       File containing the DeepSeek API key / 包含 DeepSeek API Key 的文件
  --timeout SECONDS         Request timeout, default 60 / 请求超时秒数，默认 60
  -h, --help                Show this help / 显示此帮助`;

function failConfiguration(message) {
  // Configuration errors use exit code 2 / 配置错误使用退出码 2
  console.error(`Configuration error / 配置错误: ${message}`);
  process.exit(2);
}

function failSearch(message) {
  // Network and API errors use exit code 1 / 网络和 API 错误使用退出码 1
  console.error(`Search failed / 搜索失败: ${message}`);
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
    query: null,
    count: 10,
    oriQuestion: null,
    localization: null,
    needContent: false,
    apiKeyFile: null,
    timeout: 60,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "-h" || arg === "--help") {
      console.log(HELP);
      process.exit(0);
    }
    if (arg === "--need-content") {
      options.needContent = true;
      continue;
    }
    if (arg === "--count") {
      const value = requireValue(argv, index, arg);
      if (!/^\d+$/.test(value)) {
        failConfiguration("--count must be an integer / --count 必须是整数");
      }
      options.count = Number(value);
      index += 1;
      continue;
    }
    if (arg === "--ori-question") {
      options.oriQuestion = requireValue(argv, index, arg);
      index += 1;
      continue;
    }
    if (arg === "--localization") {
      options.localization = requireValue(argv, index, arg);
      index += 1;
      continue;
    }
    if (arg === "--api-key-file") {
      options.apiKeyFile = requireValue(argv, index, arg);
      index += 1;
      continue;
    }
    if (arg === "--timeout") {
      const value = requireValue(argv, index, arg);
      options.timeout = Number(value);
      index += 1;
      continue;
    }
    if (arg.startsWith("-")) {
      failConfiguration(`unknown option / 未知选项: ${arg}`);
    }
    if (options.query !== null) {
      failConfiguration(`only one query is allowed / 只允许一个查询词`);
    }
    options.query = arg;
  }

  if (options.query === null) {
    failConfiguration("query is required / 必须提供查询词");
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
  // Validate API constraints before network access / 联网前校验 API 限制
  const query = options.query.trim();
  if ([...query].length < 1 || [...query].length > 128) {
    throw new Error(
      "query must contain 1-128 Unicode characters / query 必须包含 1 至 128 个 Unicode 字符",
    );
  }
  if (!Number.isInteger(options.count) || options.count < 1 || options.count > 50) {
    throw new Error("--count must be between 1 and 50 / --count 必须在 1 至 50 之间");
  }
  if (!Number.isFinite(options.timeout) || options.timeout <= 0) {
    throw new Error("--timeout must be greater than zero / --timeout 必须大于零");
  }

  const payload = { query, count: options.count };
  if (options.oriQuestion !== null) {
    const originalQuestion = options.oriQuestion.trim();
    if (
      [...originalQuestion].length < 1
      || [...originalQuestion].length > 128
    ) {
      throw new Error(
        "--ori-question must contain 1-128 Unicode characters / "
          + "--ori-question 必须包含 1 至 128 个 Unicode 字符",
      );
    }
    payload.ori_question = originalQuestion;
  }
  if (options.localization !== null) {
    payload.localization = options.localization;
  }
  if (options.needContent) {
    payload.need_content = true;
  }
  return payload;
}

async function search(payload, apiKey, timeout) {
  // Send a JSON POST request / 发送 JSON POST 请求
  let response;
  try {
    response = await fetch(API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "User-Agent": "codex-deepseek-search/1.0",
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

  try {
    return JSON.parse(rawBody);
  } catch {
    throw new Error("DeepSeek returned non-JSON content / DeepSeek 返回了非 JSON 内容");
  }
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
    result = await search(payload, apiKey, options.timeout);
  } catch (error) {
    failSearch(error.message);
  }

  // Emit machine-readable JSON / 输出机器可读 JSON
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => failSearch(error.message));
