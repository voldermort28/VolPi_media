const fs = require("fs");
const path = require("path");

const CONFIG_FILE = path.join(__dirname, "config.json");

const DEFAULT_CONFIG = {
  xoilacBaseUrl: "https://xoilaczzw.cc",
  socoliveBaseUrl: "https://socolive2.top",
  gavangBaseUrl: "https://gavang1.xyz",
  veboBaseUrl: "https://vebozbn.cc",
  vlxxBaseUrl: "https://vlxx.phd",
  viet69BaseUrl: "https://viet69.be",
  xnhauBaseUrl: "https://xnhau.pink",
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
    if (currentConfig.gavangBaseUrl) {
      currentConfig.gavangBaseUrl = currentConfig.gavangBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.gavangBaseUrl.startsWith("http://") && !currentConfig.gavangBaseUrl.startsWith("https://")) {
        currentConfig.gavangBaseUrl = "https://" + currentConfig.gavangBaseUrl;
      }
    }
    if (currentConfig.veboBaseUrl) {
      currentConfig.veboBaseUrl = currentConfig.veboBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.veboBaseUrl.startsWith("http://") && !currentConfig.veboBaseUrl.startsWith("https://")) {
        currentConfig.veboBaseUrl = "https://" + currentConfig.veboBaseUrl;
      }
    }
    if (currentConfig.vlxxBaseUrl) {
      currentConfig.vlxxBaseUrl = currentConfig.vlxxBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.vlxxBaseUrl.startsWith("http://") && !currentConfig.vlxxBaseUrl.startsWith("https://")) {
        currentConfig.vlxxBaseUrl = "https://" + currentConfig.vlxxBaseUrl;
      }
    }
    if (currentConfig.viet69BaseUrl) {
      currentConfig.viet69BaseUrl = currentConfig.viet69BaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.viet69BaseUrl.startsWith("http://") && !currentConfig.viet69BaseUrl.startsWith("https://")) {
        currentConfig.viet69BaseUrl = "https://" + currentConfig.viet69BaseUrl;
      }
    }
    if (currentConfig.xnhauBaseUrl) {
      currentConfig.xnhauBaseUrl = currentConfig.xnhauBaseUrl.trim().replace(/\/+$/, "");
      if (!currentConfig.xnhauBaseUrl.startsWith("http://") && !currentConfig.xnhauBaseUrl.startsWith("https://")) {
        currentConfig.xnhauBaseUrl = "https://" + currentConfig.xnhauBaseUrl;
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
