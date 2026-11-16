const fs = require("fs");
const path = require("path");

const CONFIG_FILE = path.join(__dirname, "config.json");

const DEFAULT_CONFIG = {
  xoilacBaseUrl: "https://xoilaczcn.tv",
  socoliveBaseUrl: "https://socolive377.co",
  gavangBaseUrl: "https://gavang3.tv",
  veboBaseUrl: "https://vebozbn.cc",
  vlxxBaseUrl: "https://vlxx.net",
  viet69BaseUrl: "https://viet69.be",
  xnhauBaseUrl: "https://xnhau.pink",
  qmhBaseUrl: "https://qmhphimsex.com",
  yumeiBaseUrl: "https://yumei-anime.com",
  autoCleanCache: true,
};

const URL_KEYS = [
  "xoilacBaseUrl",
  "socoliveBaseUrl",
  "gavangBaseUrl",
  "veboBaseUrl",
  "vlxxBaseUrl",
  "viet69BaseUrl",
  "xnhauBaseUrl",
  "qmhBaseUrl",
  "yumeiBaseUrl",
];

function normalizeUrl(val, fallback) {
  if (typeof val !== "string" || !val.trim()) {
    return fallback;
  }
  let clean = val.trim().replace(/\/+$/, "");
  if (!clean.startsWith("http://") && !clean.startsWith("https://")) {
    clean = "https://" + clean;
  }
  return clean;
}

let currentConfig = { ...DEFAULT_CONFIG };

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
      const merged = { ...DEFAULT_CONFIG, ...data };
      for (const key of URL_KEYS) {
        merged[key] = normalizeUrl(data[key], DEFAULT_CONFIG[key]);
      }
      currentConfig = merged;
    } else {
      saveConfig(DEFAULT_CONFIG);
    }
  } catch (err) {
    console.error("Error loading config:", err.message);
    currentConfig = { ...DEFAULT_CONFIG };
  }
  return currentConfig;
}

function saveConfig(newConfig = {}) {
  try {
    const updated = { ...currentConfig };
    for (const key of URL_KEYS) {
      if (newConfig[key] !== undefined && String(newConfig[key]).trim() !== "") {
        updated[key] = normalizeUrl(newConfig[key], currentConfig[key] || DEFAULT_CONFIG[key]);
      } else {
        updated[key] = normalizeUrl(currentConfig[key], DEFAULT_CONFIG[key]);
      }
    }
    if (typeof newConfig.autoCleanCache === "boolean") {
      updated.autoCleanCache = newConfig.autoCleanCache;
    }
    currentConfig = updated;
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(currentConfig, null, 2), "utf8");
    return true;
  } catch (err) {
    console.error("Error saving config:", err.message);
    return false;
  }
}

function getConfig() {
  return currentConfig;
}

// Initial load
loadConfig();

module.exports = {
  getConfig,
  saveConfig,
  loadConfig,
};
