#!/usr/bin/env node
/**
 * 把 chatbox-unbound 发布到 GitHub（不需要本机装 git）。
 *
 * 用法：
 *   $env:GITHUB_TOKEN="ghp_xxx"          # 需要 repo 权限的 PAT
 *   node publish-github.mjs --repo chatbox-unbound --description "Chatbox 解除限制插件"
 *   可选：--private 建私有仓库；--owner 指定组织
 *
 * 做三件事：
 *   1. 取 token 对应账号（GET /user）
 *   2. 建仓库（已存在就复用）
 *   3. 逐个文件走 Contents API 上传（已存在则按 sha 覆盖）
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SELF = path.dirname(fileURLToPath(import.meta.url));
const TOKEN = String(process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "").trim();
const API = "https://api.github.com";

const args = process.argv.slice(2);
const flag = (name, fallback = "") => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const REPO = flag("repo", "chatbox-unbound");
const OWNER = flag("owner", "");
const DESCRIPTION = flag("description", "Chatbox 解除限制插件：系统提示注入 + 技能 + MCP 工具 + 可点击拖拽的 q 弹小人");
const PRIVATE = args.includes("--private");

const SKIP_DIRS = new Set(["node_modules", ".git", ".github"]);
const SKIP_FILES = /(^|[\\/])(_live.*\.png|_pet.*|.*\.tmp-\d+|.*\.log|\.DS_Store)$/;

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

async function gh(method, url, body) {
  const res = await fetch(`${API}${url}`, {
    method,
    headers: {
      authorization: `Bearer ${TOKEN}`,
      accept: "application/vnd.github+json",
      "user-agent": "chatbox-unbound-publisher",
      "x-github-api-version": "2022-11-28",
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) {
    const message = data?.message || res.statusText;
    const err = new Error(`${method} ${url} -> ${res.status} ${message}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function collect(dir, base = dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") && entry.name !== ".gitignore") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      collect(full, base, out);
    } else if (entry.isFile()) {
      if (SKIP_FILES.test(full)) continue;
      out.push({ full, rel: path.relative(base, full).split(path.sep).join("/") });
    }
  }
  return out;
}

async function main() {
  if (!TOKEN) fail("没有 GITHUB_TOKEN。先设置：$env:GITHUB_TOKEN=\"ghp_...\"（需要 repo 权限）");

  const me = await gh("GET", "/user");
  const owner = OWNER || me.login;
  console.log(`账号: ${me.login}${owner !== me.login ? `（发布到 ${owner}）` : ""}`);

  let repoUrl = "";
  try {
    const repo = await gh("POST", owner === me.login ? "/user/repos" : `/orgs/${owner}/repos`, {
      name: REPO,
      description: DESCRIPTION,
      private: PRIVATE,
      auto_init: false,
      has_issues: true,
      has_wiki: false,
    });
    repoUrl = repo.html_url;
    console.log(`已创建仓库: ${repoUrl}`);
  } catch (error) {
    if (error.status === 422) {
      const repo = await gh("GET", `/repos/${owner}/${REPO}`);
      repoUrl = repo.html_url;
      console.log(`仓库已存在，复用: ${repoUrl}`);
    } else {
      throw error;
    }
  }

  const files = collect(SELF);
  console.log(`准备上传 ${files.length} 个文件`);

  const existing = new Map();
  try {
    const tree = await gh("GET", `/repos/${owner}/${REPO}/git/trees/HEAD?recursive=1`);
    for (const item of tree.tree || []) existing.set(item.path, item.sha);
  } catch { /* 空仓库 */ }

  let uploaded = 0;
  for (const file of files) {
    const content = fs.readFileSync(file.full);
    const body = {
      message: existing.has(file.rel) ? `Update ${file.rel}` : `Add ${file.rel}`,
      content: content.toString("base64"),
      branch: "main",
    };
    if (existing.has(file.rel)) body.sha = existing.get(file.rel);
    try {
      await gh("PUT", `/repos/${owner}/${REPO}/contents/${encodeURI(file.rel)}`, body);
      uploaded += 1;
      console.log(`  + ${file.rel}`);
    } catch (error) {
      console.warn(`  ! ${file.rel}: ${error.message}`);
    }
  }

  console.log(`完成：${uploaded}/${files.length} 个文件已上传`);
  console.log(`仓库地址: ${repoUrl}`);
}

main().catch((error) => fail(error.message));
