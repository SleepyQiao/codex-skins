"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
let payloadFile = "";
let requestFile = "";
let lockDir = "";

class LauncherError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

function fail(message, exitCode = 1) {
  throw new LauncherError(message, exitCode);
}

function cleanup() {
  for (const file of [payloadFile, requestFile]) {
    if (file) fs.rmSync(file, { force: true });
  }
  if (lockDir) {
    fs.rmSync(path.join(lockDir, "pid"), { force: true });
    try { fs.rmdirSync(lockDir); } catch {}
  }
}

process.on("exit", cleanup);

function usage() {
  fail("Usage: ./apply-mac-skin.sh <skin-id> [--app-path PATH] [--port N] [--timeout N]", 2);
}
function requiredOption(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) fail(`Missing ${name}.`);
  return process.argv[index + 1];
}
function positive(value, label) {
  if (!/^\d+$/.test(String(value)) || Number(value) <= 0) fail(`${label} must be a positive integer.`);
}

function run(command, args, options = {}) {
  try {
    return execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options }).trim();
  } catch (error) {
    const detail = error.stderr?.toString().trim() || error.message;
    throw new LauncherError(detail);
  }
}

function plistValue(app, key) {
  const plist = path.join(app, "Contents", "Info.plist");
  if (!fs.existsSync(plist)) return "";
  try {
    return run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plist]);
  } catch {
    try {
      return run("defaults", ["read", path.join(app, "Contents", "Info"), key]);
    } catch {
      return "";
    }
  }
}

function executableForApp(app) {
  const name = plistValue(app, "CFBundleExecutable");
  if (!name || name.includes("/") || name.includes("..")) fail(`Could not read a safe CFBundleExecutable from ${app}/Contents/Info.plist.`);
  const executable = path.join(app, "Contents", "MacOS", name);
  if (!fs.existsSync(executable)) fail(`Application executable is missing: ${executable}`);
  return executable;
}

function nodeForApp(app) {
  const bundled = path.join(app, "Contents", "Resources", "cua_node", "bin", "node");
  for (const candidate of [bundled, process.execPath]) {
    if (!fs.existsSync(candidate)) continue;
    const result = spawnSync(candidate, ["-e", "process.exit(typeof WebSocket === 'function' ? 0 : 1)"], { stdio: "ignore" });
    if (result.status === 0) return candidate;
  }
  fail("No Node runtime with built-in WebSocket was found. Use a Codex.app bundle that includes cua_node.");
}

function resolveApp(requested) {
  if (requested) {
    if (!fs.statSync(requested, { throwIfNoEntry: false })?.isDirectory()) fail(`The --app-path bundle does not exist: ${requested}`);
    return requested;
  }
  for (const candidate of [
    "/Applications/Codex.app",
    path.join(process.env.HOME || "", "Applications", "Codex.app"),
    "/Applications/ChatGPT.app",
    path.join(process.env.HOME || "", "Applications", "ChatGPT.app"),
  ]) {
    if (fs.statSync(candidate, { throwIfNoEntry: false })?.isDirectory()) return candidate;
  }
  fail("No Codex or ChatGPT bundle was found. Provide --app-path /path/to/Codex.app.");
}

function safeChild(rootPath, relative, label, optional = false) {
  if ((relative == null || relative === "") && optional) return "";
  if (typeof relative !== "string" || !relative || path.isAbsolute(relative) || relative.includes("\\") || relative.includes(":")) fail(`${label} must be a safe relative path.`);
  const target = path.resolve(rootPath, relative);
  if (!target.startsWith(`${rootPath}${path.sep}`) || !fs.existsSync(target)) fail(`${label} does not exist.`);
  return target;
}

function mimeFor(file) {
  const extension = path.extname(file).toLowerCase();
  return extension === ".png" ? "image/png" : extension === ".webp" ? "image/webp" : "image/jpeg";
}

function buildExpression(skin) {
  const manifestPath = path.join(skin, "skin.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.schemaVersion !== 1 || manifest.kind !== "dream" || typeof manifest.name !== "string" || !manifest.name.trim()) fail("skin.json must declare schemaVersion 1, kind dream, and a name.");
  const background = safeChild(skin, manifest.background, "background");
  const themePath = safeChild(skin, manifest.theme, "theme");
  const stylePath = safeChild(skin, manifest.style, "style", true);
  const theme = JSON.parse(fs.readFileSync(themePath, "utf8"));
  if (!theme || typeof theme !== "object" || !["system", "light", "dark"].includes(theme.appearance)) fail("theme.json must declare appearance as system, light, or dark.");
  const css = fs.readFileSync(path.join(root, "runtime", "dream-skin.css"), "utf8");
  let renderer = fs.readFileSync(path.join(root, "runtime", "renderer-inject.js"), "utf8");
  const style = stylePath ? fs.readFileSync(stylePath, "utf8") : "";
  const replacements = {
    __DREAM_SKIN_CSS_JSON__: JSON.stringify(`${css}\n${style}`),
    __DREAM_SKIN_ART_JSON__: JSON.stringify(`data:${mimeFor(background)};base64,${fs.readFileSync(background).toString("base64")}`),
    __DREAM_SKIN_THEME_JSON__: JSON.stringify(theme),
    __DREAM_SKIN_VERSION_JSON__: JSON.stringify("standalone-codex-skin-1"),
    __DREAM_SKIN_STYLE_REVISION_JSON__: JSON.stringify(`standalone-${theme.id || "custom"}-${style.length}`),
  };
  for (const [token, value] of Object.entries(replacements)) {
    if (!renderer.includes(token)) fail(`renderer-inject.js is missing ${token}`);
    renderer = renderer.split(token).join(value);
  }
  return { expression: renderer, name: manifest.name };
}

function acquireLock(port) {
  const base = path.join(process.env.TMPDIR || "/tmp", `codex-skin-${port}.lock`);
  try {
    fs.mkdirSync(base);
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    const pidPath = path.join(base, "pid");
    const owner = Number(fs.existsSync(pidPath) ? fs.readFileSync(pidPath, "utf8").trim() : 0);
    let active = false;
    if (Number.isInteger(owner) && owner > 0) {
      try { process.kill(owner, 0); active = true; } catch {}
    }
    if (active) fail(`Another skin application is already running (PID ${owner}). Wait for it to finish or stop it before retrying.`);
    fs.rmSync(pidPath, { force: true });
    try { fs.rmdirSync(base); } catch { fail(`Could not clear stale skin lock at ${base}.`); }
    fs.mkdirSync(base);
  }
  lockDir = base;
  fs.writeFileSync(path.join(lockDir, "pid"), `${process.pid}\n`);
}

async function targetForPort(port) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: controller.signal });
    if (!response.ok) return "";
    const pages = await response.json();
    if (!Array.isArray(pages)) return "";
    const valid = pages.filter((page) => page?.type === "page" && typeof page.webSocketDebuggerUrl === "string");
    return valid.find((page) => page.url === "app://-/index.html")?.webSocketDebuggerUrl || (valid.length === 1 ? valid[0].webSocketDebuggerUrl : "");
  } catch {
    return "";
  } finally {
    clearTimeout(timer);
  }
}

function cdpEval(node, ws, expression) {
  requestFile = path.join(process.env.TMPDIR || "/tmp", `codex-skin-cdp-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(requestFile, JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression, returnByValue: true } }));
  const helper = String.raw`
const fs = require("fs");
const ws = new WebSocket(process.argv[1]);
const payload = fs.readFileSync(process.argv[2], "utf8");
let done = false;
const finish = (code, message) => { if (done) return; done = true; clearTimeout(timer); try { ws.close(); } catch {} if (message) console.error(message); process.exit(code); };
const timer = setTimeout(() => finish(1, "CDP WebSocket timed out after 5 seconds"), 5000);
ws.addEventListener("open", () => ws.send(payload));
ws.addEventListener("error", () => finish(1, "CDP WebSocket error"));
ws.addEventListener("message", (event) => { const message = JSON.parse(typeof event.data === "string" ? event.data : Buffer.from(event.data).toString("utf8")); if (message.id !== 1) return; if (message.error) finish(1, JSON.stringify(message.error)); else if (message.result?.exceptionDetails) finish(1, JSON.stringify(message.result.exceptionDetails)); else finish(0); });`;
  const result = spawnSync(node, ["-e", helper, ws, requestFile], { encoding: "utf8" });
  if (result.status !== 0) fail(result.stderr.trim() || "CDP injection failed.");
}

function quitRunning(bundleId) {
  if (!bundleId) return;
  spawnSync("osascript", ["-e", `tell application id "${bundleId}" to quit`], { stdio: "ignore" });
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function waitForTarget(port, timeout) {
  const deadline = Date.now() + timeout * 1000;
  while (Date.now() < deadline) {
    const ws = await targetForPort(port);
    if (ws) return ws;
    await delay(1000);
  }
  return "";
}

async function main() {
  const args = process.argv.slice(2);
  if (!args.length) usage();
  const id = args.shift();
  if (!id || id.includes("/") || id.includes("\\") || id.includes("..")) fail("Skin id must not contain '/', '\\', or '..'.");
  let app = "";
  let port = 9222;
  let timeout = 20;
  while (args.length) {
    const option = args.shift();
    if (!args.length && ["--app-path", "--port", "--timeout"].includes(option)) usage();
    if (option === "--app-path") app = args.shift();
    else if (option === "--port") port = Number(args.shift());
    else if (option === "--timeout") timeout = Number(args.shift());
    else fail(`Unknown option: ${option}`);
  }
  positive(port, "Port");
  if (port > 65535) fail("Port must be between 1 and 65535.");
  positive(timeout, "Timeout");
  acquireLock(port);
  const skin = path.join(root, "skins", id);
  for (const file of [path.join(root, "runtime", "dream-skin.css"), path.join(root, "runtime", "renderer-inject.js"), path.join(skin, "skin.json"), path.join(skin, "theme.json"), path.join(skin, "background.jpg")]) {
    if (!fs.existsSync(file)) fail(`Required skin asset is missing: ${file}`);
  }
  const built = buildExpression(skin);
  app = resolveApp(app);
  const node = nodeForApp(app);
  let ws = await targetForPort(port);
  if (!ws) {
    executableForApp(app);
    quitRunning(plistValue(app, "CFBundleIdentifier"));
    spawnSync("open", ["-n", app, "--args", `--remote-debugging-port=${port}`], { stdio: "ignore" });
    ws = await waitForTarget(port, timeout);
  }
  if (!ws) fail(`CDP did not expose a usable page at http://127.0.0.1:${port}/json/list within ${timeout} seconds.`);
  cdpEval(node, ws, built.expression);
  process.stdout.write(`Applied skin: ${built.name}\n`);
}

async function windowsMain() {
  const expressionFile = requiredOption("--expression-file");
  const websocketUrl = requiredOption("--websocket-url");
  const expression = fs.readFileSync(expressionFile, "utf8");
  cdpEval(process.execPath, websocketUrl, expression);
}

const platformIndex = process.argv.indexOf("--platform");
const entry = platformIndex >= 0 && process.argv[platformIndex + 1] === "windows" ? windowsMain : main;
entry().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(error.exitCode || 1);
});
