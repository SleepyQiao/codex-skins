"use strict";

const fs = require("fs");

function requiredOption(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error(`Missing ${name}.`);
  }
  return process.argv[index + 1];
}

const websocketUrl = requiredOption("--websocket-url");
const expressionFile = requiredOption("--expression-file");
const expression = fs.readFileSync(expressionFile, "utf8");
const request = JSON.stringify({
  id: 1,
  method: "Runtime.evaluate",
  params: { expression, returnByValue: true, awaitPromise: false },
});

let finished = false;
const finish = (code, message) => {
  if (finished) return;
  finished = true;
  clearTimeout(timer);
  if (message) process.stderr.write(`${message}\n`);
  process.exit(code);
};

const timer = setTimeout(() => finish(1, "CDP WebSocket timed out after 5 seconds."), 5000);
const socket = new WebSocket(websocketUrl);
socket.addEventListener("open", () => socket.send(request));
socket.addEventListener("error", () => finish(1, "CDP WebSocket error."));
socket.addEventListener("message", (event) => {
  let response;
  try {
    response = JSON.parse(typeof event.data === "string" ? event.data : Buffer.from(event.data).toString("utf8"));
  } catch {
    finish(1, "CDP returned invalid JSON.");
    return;
  }
  if (response.id !== 1) return;
  if (response.error) {
    finish(1, `CDP protocol error: ${JSON.stringify(response.error)}`);
  } else if (response.result?.exceptionDetails) {
    finish(1, `Runtime.evaluate exception: ${JSON.stringify(response.result.exceptionDetails)}`);
  } else if (!response.result) {
    finish(1, "CDP did not return a Runtime.evaluate result.");
  } else {
    finish(0);
  }
});
