const fs = require("fs");
const path = require("path");

const CONFIG_FILE = path.join(__dirname, "config.json");

const DEFAULT_CONFIG = {
  xoilacBaseUrl: "https://xoilaczzw.cc",
  socoliveBaseUrl: "https://webfifa55.live",
  vlxxBaseUrl: "https://vlxx.phd",
  yumeiBaseUrl: "https://yumei-anime.com",
  autoCleanCache: true,
};

let currentConfig = { ...DEFAULT_CONFIG };

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = fs.readFileSync(CONFIG_FILE, "utf8");
      currentConfig = { ...DEFAULT_CONFIG, ...JSON.parse(data) };
    } else {
      saveConfig(DEFAULT_CONFIG);
    }
  } catch (err) {
    console.error("Error loading config:", err.message);
    currentConfig = { ...DEFAULT_CONFIG };
  }
  return currentConfig;
}

function saveConfig(newConfig) {
  try {
    currentConfig = { ...currentConfig, ...newConfig };
    if (currentConfig.xoilacBaseUrl) {
      currentConfig.xoilacBaseUrl = currentConfig.xoilacBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.xoilacBaseUrl.startsWith("http://") && !currentConfig.xoilacBaseUrl.startsWith("https://")) {
        currentConfig.xoilacBaseUrl = "https://" + currentConfig.xoilacBaseUrl;
      }
    }
    if (currentConfig.socoliveBaseUrl) {
      currentConfig.socoliveBaseUrl = currentConfig.socoliveBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.socoliveBaseUrl.startsWith("http://") && !currentConfig.socoliveBaseUrl.startsWith("https://")) {
        currentConfig.socoliveBaseUrl = "https://" + currentConfig.socoliveBaseUrl;
      }
    }
    if (currentConfig.vlxxBaseUrl) {
      currentConfig.vlxxBaseUrl = currentConfig.vlxxBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.vlxxBaseUrl.startsWith("http://") && !currentConfig.vlxxBaseUrl.startsWith("https://")) {
        currentConfig.vlxxBaseUrl = "https://" + currentConfig.vlxxBaseUrl;
      }
    }
    if (currentConfig.yumeiBaseUrl) {
      currentConfig.yumeiBaseUrl = currentConfig.yumeiBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.yumeiBaseUrl.startsWith("http://") && !currentConfig.yumeiBaseUrl.startsWith("https://")) {
        currentConfig.yumeiBaseUrl = "https://" + currentConfig.yumeiBaseUrl;
      }
    }
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
