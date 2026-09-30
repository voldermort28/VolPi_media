const express = require("express");
const axios = require("axios");
const cheerio = require("cheerio");
const path = require("path");
const fs = require("fs");
const { getRouter } = require("stremio-addon-sdk");

const config = require("./config");
const unifiedAddon = require("./addon");
const vlxxAddon = require("./addons/vlxxAddon");
const xoilacAddon = require("./addons/xoilacAddon");
const yumeiAddon = require("./addons/yumeiAddon");
const vlxxScraper = require("./scrapers/vlxx");
const xoilacScraper = require("./scrapers/xoilac");
const yumeiScraper = require("./scrapers/yumei");
const iptvService = require("./services/iptvService");
const authService = require("./services/authService");

const app = express();
const PORT = process.env.PORT || 7000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "*");
  res.header("Access-Control-Allow-Methods", "*");
  res.header("Cache-Control", "no-cache, no-store, must-revalidate");
  if (req.method === "OPTIONS") {
    return res.sendStatus(204);
  }
  next();
});

// -------------------------------------------------------------
// AUTHENTICATION & PROTECTED PAGE ROUTING
// -------------------------------------------------------------

// Serve Login Page
app.get(["/login", "/login.html"], (req, res) => {
  const token = authService.extractToken(req);
  if (token && authService.validateSession(token)) {
    const redirect = req.query.redirect || "/";
    return res.redirect(redirect);
  }
  return res.sendFile(path.join(__dirname, "public", "login.html"));
});

// Serve Dedicated IPTV Portal Page (Protected)
app.get(["/iptv", "/iptv.html"], authService.requireAuth, (req, res) => {
  return res.sendFile(path.join(__dirname, "public", "iptv.html"));
});

// Serve Main Web Dashboard (Protected)
app.get(["/", "/index.html"], authService.requireAuth, (req, res) => {
  return res.sendFile(path.join(__dirname, "public", "index.html"));
});

// Auth API Endpoints
app.post("/api/login", (req, res) => {
  const { username, password, rememberMe } = req.body || {};
  const result = authService.login(username, password, rememberMe !== false);
  if (result.success) {
    res.cookie("volpi_session", result.token, {
      maxAge: (result.maxAgeSeconds || 86400) * 1000,
      httpOnly: true,
      sameSite: "lax",
      path: "/",
    });
    return res.json(result);
  }
  return res.status(401).json(result);
});

app.post("/api/logout", (req, res) => {
  const token = authService.extractToken(req);
  authService.logout(token);
  res.clearCookie("volpi_session", { path: "/" });
  return res.json({ success: true });
});

app.get("/api/auth-status", (req, res) => {
  const token = authService.extractToken(req);
  const session = authService.validateSession(token);
  if (session) {
    return res.json({ authenticated: true, username: session.username });
  }
  return res.json({ authenticated: false });
});

app.post("/api/change-password", authService.requireAuth, (req, res) => {
  const { username, currentPassword, newPassword } = req.body || {};
  const user = req.user ? req.user.username : (username || "admin");
  const result = authService.changePassword(user, currentPassword, newPassword);
  if (result.success) {
    res.clearCookie("volpi_session", { path: "/" });
    return res.json(result);
  }
  return res.status(400).json(result);
});

// Static assets for Web Frontend (index: false prevents bypassing auth guard)
app.use(express.static(path.join(__dirname, "public"), { index: false }));

// OTA App Version & Update Endpoints
const OTA_DEPLOY_TOKEN = process.env.OTA_DEPLOY_TOKEN || "volpi_ota_deploy_secret_9988";

app.get("/api/version", (req, res) => {
  const versionFile = path.join(__dirname, "version.json");
  if (fs.existsSync(versionFile)) {
    try {
      const data = JSON.parse(fs.readFileSync(versionFile, "utf-8"));
      return res.json(data);
    } catch (e) {
      console.error("Error reading version.json:", e);
    }
  }

  return res.json({
    version: "1.0.4",
    build: 5,
    tag_name: "v1.0.4",
    changelog: "• Cập nhật tính năng OTA Update tự động trong ứng dụng.\n• Hỗ trợ cập nhật 1 chạm cho Android TV / Điện thoại và iOS (TrollStore).\n• Tối ưu hóa hiệu năng và kết nối phát trực tiếp.",
    apkUrl: "https://stremio.laboon.vn/download/VolPi-Media-AndroidTV.apk",
    ipaUrl: "https://stremio.laboon.vn/download/VolPi-Media-iOS.ipa",
    published_at: new Date().toISOString()
  });
});

// Serve Download Landing Page
app.get(["/download", "/download/"], (req, res) => {
  res.sendFile(path.join(__dirname, "public", "download", "index.html"));
});

// Endpoint to update version info via JSON
app.post("/api/update-version-info", (req, res) => {
  const token = req.query.token || req.headers["x-upload-token"] || (req.body && req.body.token);
  if (token !== OTA_DEPLOY_TOKEN) {
    return res.status(403).json({ error: "Unauthorized" });
  }

  const versionFile = path.join(__dirname, "version.json");
  let data = {};
  if (fs.existsSync(versionFile)) {
    try {
      data = JSON.parse(fs.readFileSync(versionFile, "utf-8"));
    } catch (e) {}
  }

  if (req.body.version) data.version = req.body.version.replace(/^v/i, "");
  if (req.body.build) data.build = parseInt(req.body.build, 10);
  if (req.body.tag_name) data.tag_name = req.body.tag_name;
  if (req.body.changelog) data.changelog = req.body.changelog;
  if (req.body.apkUrl) data.apkUrl = req.body.apkUrl;
  if (req.body.ipaUrl) data.ipaUrl = req.body.ipaUrl;
  data.updated_at = new Date().toISOString();

  fs.writeFileSync(versionFile, JSON.stringify(data, null, 2), "utf-8");
  return res.json({ success: true, versionInfo: data });
});

// Endpoint to stream-upload release binary (.apk or .ipa) with auto-cleanup of old versions
app.post("/api/upload-release", (req, res) => {
  const token = req.query.token || req.headers["x-upload-token"];
  if (token !== OTA_DEPLOY_TOKEN) {
    return res.status(403).json({ error: "Unauthorized" });
  }

  const filename = req.query.filename;
  if (!filename || (!filename.endsWith(".apk") && !filename.endsWith(".ipa") && !filename.endsWith(".zip"))) {
    return res.status(400).json({ error: "Invalid filename. Must end with .apk, .ipa or .zip" });
  }

  const downloadDir = path.join(__dirname, "public", "download");
  if (!fs.existsSync(downloadDir)) {
    fs.mkdirSync(downloadDir, { recursive: true });
  }

  const isApk = filename.endsWith(".apk");
  const isIpa = filename.endsWith(".ipa");
  const isZip = filename.endsWith(".zip");
  const targetFilename = isApk
    ? "VolPi-Media-AndroidTV.apk"
    : (isIpa ? "VolPi-Media-iOS.ipa" : "VolPi-Media-macOS.zip");
  const tmpPath = path.join(downloadDir, `${targetFilename}.tmp`);
  const finalFilePath = path.join(downloadDir, targetFilename);

  const writeStream = fs.createWriteStream(tmpPath);
  req.pipe(writeStream);

  writeStream.on("finish", () => {
    try {
      if (!fs.existsSync(tmpPath) || fs.statSync(tmpPath).size === 0) {
        if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
        return res.status(400).json({ error: "Uploaded file is empty" });
      }

      // STORAGE CLEANUP: Delete old versions and residual files of the same type
      const files = fs.readdirSync(downloadDir);
      for (const f of files) {
        if (f !== `${targetFilename}.tmp`) {
          if (
            (isApk && f.toLowerCase().endsWith(".apk")) ||
            (isIpa && f.toLowerCase().endsWith(".ipa")) ||
            (isZip && f.toLowerCase().endsWith(".zip")) ||
            f.endsWith(".tmp") ||
            f.endsWith(".part")
          ) {
            try {
              fs.unlinkSync(path.join(downloadDir, f));
              console.log(`[Storage Cleanup] Deleted old release file: ${f}`);
            } catch (err) {
              console.error(`[Storage Cleanup Error] Failed to delete ${f}:`, err.message);
            }
          }
        }
      }

      // Atomic rename tmp file to active release filename
      fs.renameSync(tmpPath, finalFilePath);

      // Update version metadata
      const version = req.query.version;
      if (version) {
        const versionFile = path.join(__dirname, "version.json");
        const publicVersionFile = path.join(downloadDir, "version.json");
        let data = {};
        if (fs.existsSync(versionFile)) {
          try {
            data = JSON.parse(fs.readFileSync(versionFile, "utf-8"));
          } catch (e) {}
        }
        data.version = version.replace(/^v/i, "");
        data.tag_name = version.startsWith("v") ? version : `v${version}`;
        data.apkUrl = "https://stremio.laboon.vn/download/VolPi-Media-AndroidTV.apk";
        data.ipaUrl = "https://stremio.laboon.vn/download/VolPi-Media-iOS.ipa";
        data.macosUrl = "https://stremio.laboon.vn/download/VolPi-Media-macOS.zip";
        data.updated_at = new Date().toISOString();
        fs.writeFileSync(versionFile, JSON.stringify(data, null, 2), "utf-8");
        try { fs.writeFileSync(publicVersionFile, JSON.stringify(data, null, 2), "utf-8"); } catch (_) {}
      }

      const size = fs.existsSync(finalFilePath) ? fs.statSync(finalFilePath).size : 0;
      console.log(`[OTA Deploy] Successfully updated ${targetFilename} (${(size / 1024 / 1024).toFixed(2)} MB), old versions purged.`);
      return res.json({ success: true, filename: targetFilename, size, purgedOldVersions: true });
    } catch (err) {
      console.error("[OTA Deploy Error]", err);
      if (fs.existsSync(tmpPath)) {
        try { fs.unlinkSync(tmpPath); } catch (_) {}
      }
      return res.status(500).json({ error: err.message });
    }
  });

  writeStream.on("error", (err) => {
    console.error("[OTA Deploy Stream Error]", err);
    if (fs.existsSync(tmpPath)) {
      try { fs.unlinkSync(tmpPath); } catch (_) {}
    }
    return res.status(500).json({ error: err.message });
  });
});

// Endpoint to manually prune any extraneous files in download folder
app.post("/api/cleanup-downloads", (req, res) => {
  const token = req.query.token || req.headers["x-upload-token"] || (req.body && req.body.token);
  if (token !== OTA_DEPLOY_TOKEN) {
    return res.status(403).json({ error: "Unauthorized" });
  }

  const downloadDir = path.join(__dirname, "public", "download");
  if (!fs.existsSync(downloadDir)) {
    return res.json({ deleted: [] });
  }

  const keepFiles = ["VolPi-Media-AndroidTV.apk", "VolPi-Media-iOS.ipa"];
  const deleted = [];
  const files = fs.readdirSync(downloadDir);

  for (const f of files) {
    if (!keepFiles.includes(f) && (f.endsWith(".apk") || f.endsWith(".ipa") || f.endsWith(".tmp") || f.endsWith(".part"))) {
      try {
        fs.unlinkSync(path.join(downloadDir, f));
        deleted.push(f);
      } catch (e) {}
    }
  }

  return res.json({ success: true, deleted, remaining: keepFiles });
});


function escapeXml(unsafe) {
  if (!unsafe) return "";
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function splitTextLines(text, maxChars = 34, maxLines = 3) {
  if (!text) return [];
  const words = text.split(/\s+/);
  const lines = [];
  let cur = "";

  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    if ((cur ? cur + " " + w : w).length <= maxChars) {
      cur = cur ? cur + " " + w : w;
    } else {
      if (lines.length === maxLines - 1) {
        let rest = cur ? cur + " " + words.slice(i).join(" ") : words.slice(i).join(" ");
        if (rest.length > maxChars) {
          rest = rest.slice(0, maxChars - 3) + "...";
        }
        lines.push(rest);
        cur = "";
        break;
      }
      if (cur) lines.push(cur);
      cur = w;
    }
  }
  if (cur && lines.length < maxLines) {
    if (cur.length > maxChars) cur = cur.slice(0, maxChars - 3) + "...";
    lines.push(cur);
  }
  return lines;
}

const logoCache = new Map();
const vlxxPosterCache = new Map();
const yumeiPosterCache = new Map();

async function getLogoBase64(url) {
  if (!url) return null;
  if (logoCache.has(url)) return logoCache.get(url);
  try {
    const res = await axios.get(url, {
      responseType: "arraybuffer",
      headers: {
        "User-Agent": xoilacScraper.USER_AGENT,
        "Referer": xoilacScraper.getBaseUrl() + "/",
      },
      timeout: 3000,
    });
    const b64 = "data:image/png;base64," + Buffer.from(res.data).toString("base64");
    logoCache.set(url, b64);
    return b64;
  } catch (e) {
    return null;
  }
}

async function getVlxxPosterBase64(rawId) {
  const url = vlxxScraper.getBaseUrl() + "/img/" + rawId + ".jpg";
  if (vlxxPosterCache.has(url)) return vlxxPosterCache.get(url);
  try {
    const res = await axios.get(url, {
      responseType: "arraybuffer",
      headers: {
        "User-Agent": vlxxScraper.USER_AGENT,
        "Referer": vlxxScraper.getBaseUrl() + "/",
      },
      timeout: 5000,
    });
    const b64 = "data:image/jpeg;base64," + Buffer.from(res.data).toString("base64");
    vlxxPosterCache.set(url, b64);
    return b64;
  } catch (e) {
    return null;
  }
}

async function getYumeiPosterBase64(url) {
  if (!url) return null;
  if (yumeiPosterCache.has(url)) return yumeiPosterCache.get(url);
  try {
    const res = await axios.get(url, {
      responseType: "arraybuffer",
      headers: {
        "User-Agent": yumeiScraper.USER_AGENT,
        "Referer": yumeiScraper.getBaseUrl() + "/",
      },
      timeout: 6000,
    });
    const mime = url.endsWith(".png") ? "image/png" : (url.endsWith(".webp") ? "image/webp" : "image/jpeg");
    const b64 = `data:${mime};base64,` + Buffer.from(res.data).toString("base64");
    yumeiPosterCache.set(url, b64);
    return b64;
  } catch (e) {
    return null;
  }
}

// -------------------------------------------------------------
// FRONTEND API ENDPOINTS
// -------------------------------------------------------------

app.get(["/", "/admin", "/config"], (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.get("/api/status", async (req, res) => {
  const cfg = config.getConfig();
  let matchesCount = 0;
  try {
    const matches = await xoilacScraper.getLiveMatches();
    matchesCount = matches ? matches.length : 0;
  } catch (e) {}

  const uptimeSec = Math.floor(process.uptime());
  const hours = Math.floor(uptimeSec / 3600);
  const mins = Math.floor((uptimeSec % 3600) / 60);

  res.json({
    status: "ok",
    uptime: hours + "h " + mins + "m",
    config: cfg,
    matchesCount,
  });
});

app.get("/api/matches", async (req, res) => {
  try {
    const matches = await xoilacScraper.getLiveMatches();
    res.json(matches || []);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// -------------------------------------------------------------
// IPTV API ENDPOINTS
// Stream Proxy to bypass CORS / Referer restrictions
app.all("/api/iptv/stream-proxy", (req, res) => {
  return iptvService.handleStreamProxy(req, res);
});

app.get("/api/iptv/channels", async (req, res) => {
  try {
    const forAdmin = req.query.admin === "true";
    const forceRefresh = req.query.forceRefresh === "true" || !!req.query._t;
    const sourceId = req.query.sourceId || req.query.source || "";
    const category = req.query.category || req.query.type || "";
    const data = await iptvService.getChannels({ forceRefresh, forAdmin, sourceId, category });
    res.json(data);
  } catch (err) {
    console.error("Error fetching IPTV channels:", err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/iptv/sources", async (req, res) => {
  try {
    const sources = await iptvService.getSources();
    res.json(sources);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/iptv/sources/add", authService.requireAuth, (req, res) => {
  try {
    const result = iptvService.addPlaylist(req.body);
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/api/iptv/sources/delete", authService.requireAuth, (req, res) => {
  try {
    const { id } = req.body;
    const result = iptvService.deletePlaylist(id);
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/api/iptv/sources/toggle", authService.requireAuth, (req, res) => {
  try {
    const { id, enabled } = req.body;
    const result = iptvService.togglePlaylist(id, enabled);
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get("/api/iptv/config", (req, res) => {
  res.json(iptvService.loadConfig());
});

app.post("/api/iptv/set-source", authService.requireAuth, (req, res) => {
  try {
    const { type, url } = req.body;
    const cfg = iptvService.setSource(type, url);
    res.json({ success: true, config: cfg });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/api/iptv/upload-content", authService.requireAuth, (req, res) => {
  try {
    const { content, filename } = req.body;
    if (!content) return res.status(400).json({ success: false, error: "Nội dung file trống" });
    const result = iptvService.uploadM3uFile(filename || "playlist.m3u", Buffer.from(content, "utf-8"));
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/api/iptv/settings", authService.requireAuth, (req, res) => {
  try {
    const { hiddenChannelIds, pinnedChannelIds } = req.body;
    const cfg = iptvService.updateChannelSettings({ hiddenChannelIds, pinnedChannelIds });
    res.json({ success: true, config: cfg });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/api/iptv/refresh", authService.requireAuth, async (req, res) => {
  try {
    iptvService.clearCache();
    const forAdmin = req.query.admin === "true";
    const data = await iptvService.getChannels({ forceRefresh: true, forAdmin });
    const count = Array.isArray(data) ? data.length : (data.totalCount || 0);
    res.json({ success: true, count, data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get("/api/config", (req, res) => {
  res.json(config.getConfig());
});

app.post("/api/config", authService.requireAuth, (req, res) => {
  try {
    const { xoilacBaseUrl, vlxxBaseUrl, yumeiBaseUrl } = req.body;
    const saved = config.saveConfig({ xoilacBaseUrl, vlxxBaseUrl, yumeiBaseUrl });
    if (saved) {
      xoilacScraper.clearCache();
      vlxxScraper.clearCache();
      yumeiScraper.clearCache();
      logoCache.clear();
      vlxxPosterCache.clear();
      yumeiPosterCache.clear();
      return res.json({ success: true, message: "Đã cập nhật cấu hình và làm mới bộ nhớ đệm!" });
    }
    return res.status(500).json({ success: false, message: "Không thể lưu cấu hình" });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

app.post("/api/test-domain", authService.requireAuth, async (req, res) => {
  try {
    const { type, url } = req.body;
    if (!url) return res.status(400).json({ success: false, error: "Vui lòng cung cấp URL" });

    let cleanUrl = url.trim().replace(/\/+$/, "");
    if (!cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) {
      cleanUrl = "https://" + cleanUrl;
    }

    let finalOrigin = null;

    if (type === "xoilac") {
      const response = await axios.get(cleanUrl, {
        headers: {
          "User-Agent": xoilacScraper.USER_AGENT,
          "Accept-Language": "vi,en-US;q=0.9,en;q=0.8",
        },
        timeout: 8000,
        maxRedirects: 5,
      });
      if (response.request && response.request.res && response.request.res.responseUrl) {
        try {
          const fo = new URL(response.request.res.responseUrl).origin;
          if (fo !== new URL(cleanUrl).origin) finalOrigin = fo;
        } catch (e) {}
      }
      const $ = cheerio.load(response.data);
      const links = $("a[href*=\"/truc-tiep/\"]");
      if (links.length > 0) {
        return res.json({ success: true, count: links.length, redirectedUrl: finalOrigin });
      } else {
        return res.json({ success: false, error: "Trang web phản hồi nhưng không tìm thấy link trận đấu (/truc-tiep/)" });
      }
    } else if (type === "vlxx") {
      const response = await axios.get(cleanUrl, {
        headers: {
          "User-Agent": vlxxScraper.USER_AGENT,
        },
        timeout: 8000,
        maxRedirects: 5,
      });
      if (response.request && response.request.res && response.request.res.responseUrl) {
        try {
          const fo = new URL(response.request.res.responseUrl).origin;
          if (fo !== new URL(cleanUrl).origin) finalOrigin = fo;
        } catch (e) {}
      }
      const $ = cheerio.load(response.data);
      const items = $("#video-list .video-item, .video-item");
      return res.json({ success: true, count: items.length || 1, redirectedUrl: finalOrigin });
    } else if (type === "yumei") {
      const response = await axios.get(cleanUrl + "/thu-vien", {
        headers: {
          "RSC": "1",
          "User-Agent": yumeiScraper.USER_AGENT,
        },
        timeout: 8000,
      });
      const dataStr = String(response.data);
      const hasContent = dataStr.includes("Pokemon") || dataStr.includes("thu-vien");
      if (hasContent) {
        return res.json({ success: true, count: 4 });
      } else {
        return res.json({ success: false, error: "Không lấy được dữ liệu thư viện từ domain này" });
      }
    }

    return res.status(400).json({ success: false, error: "Loại domain không hợp lệ" });
  } catch (err) {
    return res.json({ success: false, error: err.message });
  }
});

// -------------------------------------------------------------
// DYNAMIC SVG THUMBNAIL GENERATORS
// -------------------------------------------------------------

// 1. VLXX Card SVG
app.get("/thumb/vlxx/:id.svg", async (req, res) => {
  try {
    const rawId = req.params.id.replace(/\.svg$/, "");
    const [info, posterB64] = await Promise.all([
      vlxxScraper.getVideoInfo(rawId),
      getVlxxPosterBase64(rawId),
    ]);

    const title = info.title || "Video " + rawId;
    const ribbon = info.ribbon || "";

    const lines = splitTextLines(title, 34, 3);
    let lineTags = "";
    if (lines.length === 1) {
      lineTags = "<text x=\"24\" y=\"325\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"24\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[0]) + "</text>";
    } else if (lines.length === 2) {
      lineTags = "<text x=\"24\" y=\"300\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"22\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[0]) + "</text>" +
        "<text x=\"24\" y=\"332\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"22\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[1]) + "</text>";
    } else {
      lineTags = "<text x=\"24\" y=\"278\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"20\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[0]) + "</text>" +
        "<text x=\"24\" y=\"308\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"20\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[1]) + "</text>" +
        "<text x=\"24\" y=\"338\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"20\" font-weight=\"800\" filter=\"url(#drop-shadow)\">" + escapeXml(lines[2]) + "</text>";
    }

    const imageTag = posterB64
      ? "<image href=\"" + posterB64 + "\" x=\"0\" y=\"0\" width=\"640\" height=\"360\" preserveAspectRatio=\"xMidYMid slice\" />"
      : "<rect width=\"640\" height=\"360\" fill=\"#0f172a\" />";

    let ribbonTag = "";
    if (ribbon) {
      const ribbonWidth = Math.min(Math.max(ribbon.length * 12 + 24, 64), 200);
      ribbonTag = "<rect x=\"18\" y=\"16\" width=\"" + ribbonWidth + "\" height=\"32\" rx=\"8\" fill=\"#e11d48\" fill-opacity=\"0.95\" stroke=\"#ffffff\" stroke-width=\"1.5\" />" +
        "<text x=\"" + (18 + ribbonWidth / 2) + "\" y=\"38\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"15\" font-weight=\"900\" text-anchor=\"middle\">" +
        escapeXml(ribbon.toUpperCase()) + "</text>";
    }

    const svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"360\" viewBox=\"0 0 640 360\">\n" +
"  <defs>\n" +
"    <linearGradient id=\"bottomGrad\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">\n" +
"      <stop offset=\"0%\" stop-color=\"#000000\" stop-opacity=\"0\" />\n" +
"      <stop offset=\"35%\" stop-color=\"#050811\" stop-opacity=\"0.75\" />\n" +
"      <stop offset=\"100%\" stop-color=\"#050811\" stop-opacity=\"0.98\" />\n" +
"    </linearGradient>\n" +
"    <filter id=\"drop-shadow\" x=\"-10%\" y=\"-10%\" width=\"120%\" height=\"120%\">\n" +
"      <feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"3\" flood-color=\"#000000\" flood-opacity=\"0.9\"/>\n" +
"    </filter>\n" +
"    <clipPath id=\"card-round\">\n" +
"      <rect width=\"640\" height=\"360\" rx=\"16\" />\n" +
"    </clipPath>\n" +
"  </defs>\n\n" +
"  <g clip-path=\"url(#card-round)\">\n" +
"    " + imageTag + "\n" +
"    <rect x=\"0\" y=\"140\" width=\"640\" height=\"220\" fill=\"url(#bottomGrad)\" />\n" +
"    " + ribbonTag + "\n" +
"    " + lineTags + "\n" +
"  </g>\n\n" +
"  <rect width=\"640\" height=\"360\" rx=\"16\" fill=\"none\" stroke=\"#334155\" stroke-width=\"2\" />\n" +
"</svg>";

    res.setHeader("Content-Type", "image/svg+xml; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=86400");
    return res.send(svg);
  } catch (err) {
    console.error("Error rendering VLXX SVG:", err.message);
    return res.status(500).send("Error");
  }
});

// VLXX Direct JPG Thumbnail Proxy (Zero disk write, lightweight stream pipe)
app.get("/thumb/vlxx/:id.jpg", async (req, res) => {
  try {
    const rawId = req.params.id.replace(/\.jpg$/, "");
    const currentBase = vlxxScraper.getBaseUrl();
    const url = `${currentBase}/img/${rawId}.jpg`;
    const imgRes = await axios.get(url, {
      responseType: "stream",
      headers: {
        "User-Agent": vlxxScraper.USER_AGENT,
      },
      timeout: 8000,
    });
    res.setHeader("Content-Type", "image/jpeg");
    res.setHeader("Cache-Control", "public, max-age=604800");
    res.setHeader("X-Accel-Buffering", "no");
    return imgRes.data.pipe(res);
  } catch (err) {
    return res.status(404).send("Image not found");
  }
});

// 2. Xôi Lạc Card SVG (Extra Large +50% & Team Highlights)
app.get("/thumb/xoilac/:slug.svg", async (req, res) => {
  try {
    const { slug } = req.params;
    const details = await xoilacScraper.getMatchDetails(slug);
    const home = details.homeTeam || "Đội nhà";
    const away = details.awayTeam || "Đội khách";
    const league = details.league || "Bóng đá";
    const time = details.time || "Trực tiếp";
    const priority = details.priority || xoilacScraper.getTeamPriority(details);

    const [homeLogoB64, awayLogoB64] = await Promise.all([
      getLogoBase64(details.homeLogo),
      getLogoBase64(details.awayLogo),
    ]);

    const homeLogoTag = homeLogoB64
      ? "<image href=\"" + homeLogoB64 + "\" x=\"92\" y=\"80\" width=\"125\" height=\"125\" preserveAspectRatio=\"xMidYMid meet\"/>"
      : "<text x=\"155\" y=\"150\" fill=\"#64748b\" font-family=\"sans-serif\" font-size=\"54\" text-anchor=\"middle\">🛡️</text>";

    const awayLogoTag = awayLogoB64
      ? "<image href=\"" + awayLogoB64 + "\" x=\"422\" y=\"80\" width=\"125\" height=\"125\" preserveAspectRatio=\"xMidYMid meet\"/>"
      : "<text x=\"485\" y=\"150\" fill=\"#64748b\" font-family=\"sans-serif\" font-size=\"54\" text-anchor=\"middle\">🛡️</text>";

    const borderColor = priority.color || "#334155";
    const borderWidth = priority.level === 1 ? "4.5" : (priority.level === 2 ? "3.5" : "2.5");
    const topBadgeBg = priority.badgeBg || "#1e293b";
    const topTextColor = priority.textColor || "#38bdf8";
    
    let topText = "🏆 " + league.toUpperCase() + "  •  ⏱️ " + time;
    if (priority.badgeText) {
      topText = priority.badgeText + " • ⏱️ " + time;
    }

    const svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"360\" viewBox=\"0 0 640 360\">\n" +
"  <defs>\n" +
"    <linearGradient id=\"bg\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\">\n" +
"      <stop offset=\"0%\" stop-color=\"#050811\"/>\n" +
"      <stop offset=\"50%\" stop-color=\"#0d1527\"/>\n" +
"      <stop offset=\"100%\" stop-color=\"#050811\"/>\n" +
"    </linearGradient>\n" +
"    <linearGradient id=\"vs\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\">\n" +
"      <stop offset=\"0%\" stop-color=\"#ef4444\"/>\n" +
"      <stop offset=\"100%\" stop-color=\"#f97316\"/>\n" +
"    </linearGradient>\n" +
"  </defs>\n\n" +
"  <rect width=\"640\" height=\"360\" rx=\"24\" fill=\"url(#bg)\" stroke=\"" + borderColor + "\" stroke-width=\"" + borderWidth + "\"/>\n" +
"  <rect x=\"12\" y=\"10\" width=\"616\" height=\"56\" rx=\"28\" fill=\"" + topBadgeBg + "\" fill-opacity=\"0.95\" stroke=\"#475569\" stroke-width=\"2\"/>\n" +
"  <text x=\"320\" y=\"46\" fill=\"" + topTextColor + "\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"23\" font-weight=\"900\" text-anchor=\"middle\">\n" +
"    " + escapeXml(topText) + "\n" +
"  </text>\n\n" +
"  <rect x=\"12\" y=\"72\" width=\"286\" height=\"224\" rx=\"20\" fill=\"#1e293b\" fill-opacity=\"0.8\" stroke=\"#334155\" stroke-width=\"2\"/>\n" +
"  " + homeLogoTag + "\n" +
"  <text x=\"155\" y=\"238\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"28\" font-weight=\"900\" text-anchor=\"middle\">\n" +
"    " + escapeXml(home) + "\n" +
"  </text>\n" +
"  <text x=\"155\" y=\"272\" fill=\"#94a3b8\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"15\" font-weight=\"800\" text-anchor=\"middle\">\n" +
"    CHỦ NHÀ\n" +
"  </text>\n\n" +
"  <circle cx=\"320\" cy=\"180\" r=\"42\" fill=\"url(#vs)\" stroke=\"#ffffff\" stroke-width=\"3\"/>\n" +
"  <text x=\"320\" y=\"190\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"28\" font-weight=\"900\" text-anchor=\"middle\">\n" +
"    VS\n" +
"  </text>\n\n" +
"  <rect x=\"342\" y=\"72\" width=\"286\" height=\"224\" rx=\"20\" fill=\"#1e293b\" fill-opacity=\"0.8\" stroke=\"#334155\" stroke-width=\"2\"/>\n" +
"  " + awayLogoTag + "\n" +
"  <text x=\"485\" y=\"238\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"28\" font-weight=\"900\" text-anchor=\"middle\">\n" +
"    " + escapeXml(away) + "\n" +
"  </text>\n" +
"  <text x=\"485\" y=\"272\" fill=\"#94a3b8\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"15\" font-weight=\"800\" text-anchor=\"middle\">\n" +
"    ĐỘI KHÁCH\n" +
"  </text>\n\n" +
"  <rect x=\"140\" y=\"304\" width=\"360\" height=\"48\" rx=\"24\" fill=\"#dc2626\"/>\n" +
"  <circle cx=\"175\" cy=\"328\" r=\"8\" fill=\"#ffffff\"/>\n" +
"  <text x=\"330\" y=\"335\" fill=\"#ffffff\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif\" font-size=\"20\" font-weight=\"900\" text-anchor=\"middle\">\n" +
"    TRỰC TIẾP • XÔI LẠC TV\n" +
"  </text>\n" +
"</svg>";

    res.setHeader("Content-Type", "image/svg+xml; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=300");
    return res.send(svg);
  } catch (err) {
    console.error("Error rendering SVG:", err.message);
    return res.status(500).send("Error");
  }
});

// 3. Yumei Anime / Tokusatsu Card SVG (Web UI Card Banner style)
app.get("/thumb/yumei/:id.svg", async (req, res) => {
  try {
    const rawId = req.params.id.replace(/\.svg$/, "");
    let meta = yumeiScraper.getCardRegistry().get(rawId);

    // If not in registry (e.g. freshly restarted server), initialize registry
    if (!meta) {
      await yumeiScraper.getCatalog("yumei-all");
      meta = yumeiScraper.getCardRegistry().get(rawId);
    }

    let title = meta?.title;
    let badge = meta?.badge || "Anime";
    let subtitle = meta?.subtitle || "";
    let bgUrl = meta?.bgUrl;

    // Fallback if still not found
    if (!title) {
      const decodedPath = yumeiScraper.decodePathId(rawId);
      const parts = decodedPath.split("/").filter(Boolean);
      const lastPart = parts[parts.length - 1] || "Yumei Anime";
      title = lastPart.replace(/^\d+-/, "").replace(/-/g, " ");
      title = title.charAt(0).toUpperCase() + title.slice(1);
    }

    // Fetch poster base64 for reliable rendering across all Stremio platforms
    const posterB64 = await getYumeiPosterBase64(bgUrl);

    // Badge width & styling
    const badgeText = badge.length > 15 ? badge.slice(0, 15) : badge;
    const badgeWidth = Math.max(badgeText.length * 11 + 32, 84);

    // Title & Subtitle typography
    const titleFontSize = title.length > 18 ? 28 : 34;
    const titleLineHeight = titleFontSize + 6;
    const titleLines = splitTextLines(title, titleFontSize > 30 ? 16 : 22, 2);

    const subLines = subtitle ? splitTextLines(subtitle, 28, 2) : [];
    
    // Calculate vertical layout
    let titleY = 345;
    if (subLines.length === 0) {
      titleY = titleLines.length === 1 ? 430 : 395;
    } else if (titleLines.length === 2) {
      titleY = 315;
    }

    const titleTags = titleLines
      .map((line, idx) => `<text x="24" y="${titleY + idx * titleLineHeight}" fill="#ffffff" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif" font-size="${titleFontSize}" font-weight="900" filter="url(#drop-shadow)">${escapeXml(line)}</text>`)
      .join("\n    ");

    const subY = titleY + (titleLines.length - 1) * titleLineHeight + 24;
    const subTags = subLines
      .map((line, idx) => `<text x="24" y="${subY + idx * 20}" fill="#cbd5e1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif" font-size="15" font-weight="500">${escapeXml(line)}</text>`)
      .join("\n    ");

    const linkY = subLines.length > 0 ? (subY + subLines.length * 20 + 16) : (titleY + (titleLines.length - 1) * titleLineHeight + 36);

    const imageTag = posterB64
      ? `<image href="${posterB64}" x="0" y="0" width="380" height="520" preserveAspectRatio="xMidYMid slice" />`
      : (bgUrl
          ? `<image href="${escapeXml(bgUrl)}" x="0" y="0" width="380" height="520" preserveAspectRatio="xMidYMid slice" />`
          : `<rect width="380" height="520" fill="#0f172a" />`);

    const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="380" height="520" viewBox="0 0 380 520">
  <defs>
    <linearGradient id="cardGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#000000" stop-opacity="0.1" />
      <stop offset="35%" stop-color="#000000" stop-opacity="0.25" />
      <stop offset="65%" stop-color="#050811" stop-opacity="0.85" />
      <stop offset="100%" stop-color="#000000" stop-opacity="0.98" />
    </linearGradient>
    <filter id="drop-shadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#000000" flood-opacity="1"/>
    </filter>
    <clipPath id="card-clip">
      <rect width="380" height="520" rx="24" />
    </clipPath>
  </defs>

  <g clip-path="url(#card-clip)">
    ${imageTag}
    <rect x="0" y="0" width="380" height="520" fill="url(#cardGrad)" />
    
    <!-- Top-left badge pill -->
    <rect x="22" y="22" width="${badgeWidth}" height="38" rx="19" fill="#000000" fill-opacity="0.65" stroke="#ffffff" stroke-opacity="0.3" stroke-width="1.5" />
    <text x="${22 + badgeWidth / 2}" y="47" fill="#ffffff" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif" font-size="16" font-weight="800" text-anchor="middle">${escapeXml(badgeText)}</text>

    <!-- Title, Subtitle, and Action -->
    ${titleTags}
    ${subTags}
    <text x="24" y="${linkY}" fill="#ffffff" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif" font-size="16" font-weight="800">Đi đến →</text>
  </g>

  <!-- Border outline -->
  <rect width="380" height="520" rx="24" fill="none" stroke="#475569" stroke-width="2" />
</svg>`;

    res.setHeader("Content-Type", "image/svg+xml; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    return res.send(svg);
  } catch (err) {
    console.error("Error rendering Yumei SVG:", err.message);
    return res.status(500).send("Error");
  }
});

// -------------------------------------------------------------
// STREMIO ADDON SDK ROUTERS
// -------------------------------------------------------------

app.use("/vlxx", getRouter(vlxxAddon));
app.use("/xoilac", getRouter(xoilacAddon));
app.use("/yumei", getRouter(yumeiAddon));
app.use(getRouter(unifiedAddon));

// -------------------------------------------------------------
// STREAM PLAYBACK PROXIES
// -------------------------------------------------------------

app.get("/hls/:id/:server/master.m3u8", async (req, res) => {
  try {
    const { id, server } = req.params;
    const rawUrl = await vlxxScraper.getRawManifestUrl(id, server);
    if (!rawUrl) {
      return res.status(404).send("Stream manifest not found");
    }

    const manifestRes = await axios.get(rawUrl, {
      headers: {
        "Referer": "https://play.vlstream.net/",
        "User-Agent": vlxxScraper.USER_AGENT,
      },
      timeout: 10000,
    });

    const host = process.env.BASE_HOST || "https://" + req.get("host");
    const lines = manifestRes.data.split("\n");
    const rewritten = lines.map((line) => {
      const trimmed = line.trim();
      if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
        return host + "/seg?u=" + encodeURIComponent(trimmed);
      }
      return line;
    }).join("\n");

    res.setHeader("Content-Type", "application/vnd.apple.mpegurl");
    res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    res.setHeader("X-Accel-Buffering", "no");
    return res.send(rewritten);
  } catch (err) {
    console.error("Error generating HLS manifest:", err.message);
    return res.status(500).send("Error loading playlist");
  }
});

app.get("/seg", async (req, res) => {
  try {
    const targetUrl = req.query.u;
    if (!targetUrl) {
      return res.status(400).send("Missing segment URL");
    }

    const segRes = await axios.get(targetUrl, {
      responseType: "arraybuffer",
      headers: {
        "User-Agent": vlxxScraper.USER_AGENT,
      },
      timeout: 15000,
    });

    const buf = Buffer.from(segRes.data);
    
    let offset = 0;
    const iendIdx = buf.indexOf("IEND");
    if (iendIdx !== -1) {
      offset = iendIdx + 8;
    } else if (buf[0] !== 0x47) {
      const firstSync = buf.indexOf(0x47);
      if (firstSync !== -1) offset = firstSync;
    }

    const tsBuf = offset > 0 ? buf.slice(offset) : buf;

    res.setHeader("Content-Type", "video/mp2t");
    res.setHeader("Content-Length", tsBuf.length);
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.setHeader("X-Accel-Buffering", "no");
    return res.send(tsBuf);
  } catch (err) {
    console.error("Error proxying TS segment:", err.message);
    return res.status(502).send("Error proxying segment");
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log("\n======================================================");
  console.log("🚀 Stremio Addon Server running on port " + PORT);
  console.log("🌐 Web Dashboard:   http://localhost:" + PORT + "/");
  console.log("👉 Yumei Anime:     http://localhost:" + PORT + "/yumei/manifest.json");
  console.log("👉 Xôi Lạc Only:    http://localhost:" + PORT + "/xoilac/manifest.json");
  console.log("👉 VLXX Only:       http://localhost:" + PORT + "/vlxx/manifest.json");
  console.log("👉 Combo Tất Cả:    http://localhost:" + PORT + "/manifest.json");
  console.log("======================================================\n");
});
