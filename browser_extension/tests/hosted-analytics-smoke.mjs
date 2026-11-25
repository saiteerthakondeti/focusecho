import puppeteer from "puppeteer";
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
// From the repository root, run: node browser_extension/tests/hosted-analytics-smoke.mjs
// Requires a Flutter web build configured for the hosted test project and
// Puppeteer's Chrome for Testing. Each run creates a hosted anonymous user.
const root = await fs.realpath("mobile_app/build/web"),
  ext = path.resolve("browser_extension");
await fs.access(path.join(root, "main.dart.js"));
const server = http.createServer(async (req, res) => {
  try {
    const file = path.join(
      root,
      decodeURIComponent(new URL(req.url, "http://localhost").pathname).replace(
        /^\/$/,
        "index.html",
      ),
    );
    const resolved = await fs.realpath(file);
    if (!resolved.startsWith(root + path.sep)) {
      res.writeHead(404);
      res.end();
      return;
    }
    const mime = {
      ".js": "application/javascript",
      ".wasm": "application/wasm",
      ".html": "text/html",
      ".json": "application/json",
      ".css": "text/css",
    };
    res.setHeader(
      "Content-Type",
      mime[path.extname(file)] || "application/octet-stream",
    );
    res.end(await fs.readFile(resolved));
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = "http://127.0.0.1:" + server.address().port;
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
async function wait(name, fn, limit = 55) {
  for (let i = 0; i < limit; i++) {
    let v = await fn();
    if (v) return v;
    await delay(1000);
  }
  throw Error("Timeout: " + name);
}
let browser, ctrl;
try {
  browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH || undefined,
    headless: true,
    enableExtensions: [ext],
    args: [
      "--enable-unsafe-swiftshader",
      "--disable-background-timer-throttling",
    ],
  });
  const target = await browser.waitForTarget(
    (t) =>
      t.type() === "service_worker" &&
      t.url().startsWith("chrome-extension://"),
  );
  const extension = new URL(target.url()).host;
  console.log("Chrome", await browser.version(), "extension", extension);
  ctrl = await browser.newPage();
  await ctrl.goto(
    "chrome-extension://" + extension + "/src/options/options.html",
  );
  const msg = (type, args = {}) =>
    ctrl.evaluate((m) => chrome.runtime.sendMessage(m), { type, ...args });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 1000 });
  const reads = [];
  const fetchedRows = new Map();
  page.on("response", async (r) => {
    const u = new URL(r.url());
    if (r.status() >= 400 && u.pathname.startsWith("/rest/"))
      console.log("HTTP", r.status(), u.pathname);
    if (u.pathname === "/auth/v1/signup")
      console.log("Hosted test-account signup", r.status());
    if (
      u.pathname === "/rest/v1/distraction_events" &&
      u.searchParams.has("triggered_at") &&
      r.request().method() === "GET" &&
      page.url().includes("/analytics")
    ) {
      try {
        const data = await r.json();
        if (Array.isArray(data)) {
          reads.push(data.map((x) => x.id));
          for (const x of data) fetchedRows.set(x.id, x);
        }
      } catch {}
    }
  });
  await page.evaluateOnNewDocument(() => {
    try {
      localStorage.setItem("flutter.consent_given", "true");
      localStorage.setItem("flutter.has_skipped_login", "true");
    } catch {}
  });
  await page.goto(url + "/#/analytics");
  console.log("Chrome extension loaded; dashboard opened");
  await wait(
    "guest account bridge",
    async () => (await msg("fe:debug_get_state")).cloud_ready,
  );
  async function enableSemantics() {
    const handle = await page.$("pierce/flt-semantics-placeholder");
    if (handle) await handle.evaluate((e) => e.click());
    await page.evaluate(() =>
      document
        .querySelector("flt-glass-pane")
        ?.shadowRoot?.querySelector("flt-semantics-placeholder")
        ?.click(),
    );
    await page.evaluate(() =>
      document.querySelector("flt-semantics-placeholder")?.click(),
    );
  }
  async function rendered(word) {
    return page.evaluate((word) => {
      function find(root) {
        for (const e of root.querySelectorAll("*")) {
          if (e.shadowRoot && find(e.shadowRoot)) return true;
          if (
            e.tagName.toLowerCase() === "flt-semantics" &&
            [e.textContent, e.getAttribute("aria-label")].some((v) =>
              v?.includes(word),
            )
          )
            return true;
        }
        return false;
      }
      return find(document);
    }, word);
  }
  await wait("initial analytics read", async () => {
    if (page.url().endsWith("#/dashboard"))
      await page.goto(url + "/#/analytics");
    return reads.length;
  });
  assert.equal(reads.at(-1).length, 0);
  await wait(
    "empty Analytics screen",
    async () => {
      await enableSemantics();
      return rendered("No distraction data yet.");
    },
    20,
  );
  console.log(
    "Baseline: fresh account, empty DB response and empty Analytics screen.",
  );
  await msg("fe:debug_start_session", {
    intention: "Hosted analytics verification",
    distraction_list: ["example.org"],
  });
  const tab = await browser.newPage();
  await tab.bringToFront();
  await tab.goto("https://example.org/", { waitUntil: "domcontentloaded" });
  const state = await wait("real Chrome distraction", async () => {
    const s = await msg("fe:debug_get_state");
    return s.distraction?.event_id && s;
  });
  const id = state.distraction.event_id,
    sid = state.session.session_id;
  console.log("Extension event", id, "session", sid);
  const row = await wait("hosted row for exact extension event", async () =>
    ctrl.evaluate(
      async ({ id, sid }) => {
        const c = await chrome.storage.local.get([
          "fe_supabase_url",
          "fe_supabase_anon_key",
          "fe_auth_token",
        ]);
        const u = new URL("/rest/v1/distraction_events", c.fe_supabase_url);
        u.search = new URLSearchParams({
          id: "eq." + id,
          session_id: "eq." + sid,
          select: "id,session_id,event_type,app_label",
        });
        const r = await fetch(u, {
          headers: {
            apikey: c.fe_supabase_anon_key,
            Authorization: "Bearer " + c.fe_auth_token,
          },
        });
        if (!r.ok)
          throw Error("User-scoped database read returned HTTP " + r.status);
        return (await r.json())[0];
      },
      { id, sid },
    ),
  );
  console.log("Hosted DB", JSON.stringify(row));
  assert.equal(row.event_type, "distraction");
  await page.bringToFront();
  await msg("fe:debug_stop_session");
  reads.length = 0;
  await page.goto(url + "/#/analytics", { waitUntil: "domcontentloaded" });
  await page.reload({ waitUntil: "domcontentloaded" });
  await wait("analytics GET includes matching UUID", async () => {
    if (page.url().endsWith("#/dashboard"))
      await page.goto(url + "/#/analytics");
    return reads.some((r) => r.includes(id));
  });
  const finalRow = fetchedRows.get(id);
  console.log(
    "Analytics GET",
    finalRow.id,
    finalRow.package_name,
    finalRow.app_label,
    page.url(),
  );
  await wait(
    "Analytics renders host",
    async () => {
      await enableSemantics();
      if (await rendered(finalRow.app_label || finalRow.package_name))
        return true;
      await page.mouse.move(600, 700);
      await page.mouse.wheel({ deltaY: 450 });
      return false;
    },
    20,
  );
  console.log(
    "PASS Analytics fetched exact event and rendered",
    finalRow.app_label,
  );
} finally {
  await browser?.close();
  server.close();
}
