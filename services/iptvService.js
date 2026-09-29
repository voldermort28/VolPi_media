const fs = require('fs');
const path = require('path');
const axios = require('axios');

const CONFIG_PATH = path.join(__dirname, '..', 'iptv_config.json');
const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');

// Default reputable public Vietnam IPTV source from iptv-org (daily automated health checks)
const DEFAULT_SOURCE_URL = 'https://iptv-org.github.io/iptv/countries/vn.m3u';

// Built-in verified backup channels in case network is down
const BUILTIN_FALLBACK_CHANNELS = [
  {
    id: 'vtv1-hd',
    name: 'VTV1 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv1.png',
    url: 'https://vtv1.vtv.vn/vtv1hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv2-hd',
    name: 'VTV2 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv2.png',
    url: 'https://vtv2.vtv.vn/vtv2hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv3-hd',
    name: 'VTV3 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv3.png',
    url: 'https://vtv3.vtv.vn/vtv3hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv4-hd',
    name: 'VTV4 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv4.png',
    url: 'https://vtv4.vtv.vn/vtv4hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv5-hd',
    name: 'VTV5 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv5.png',
    url: 'https://vtv5.vtv.vn/vtv5hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv7-hd',
    name: 'VTV7 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv7.png',
    url: 'https://vtv7.vtv.vn/vtv7hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv8-hd',
    name: 'VTV8 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv8.png',
    url: 'https://vtv8.vtv.vn/vtv8hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv9-hd',
    name: 'VTV9 HD',
    logo: 'https://vtv1.vtv.vn/Content/Images/logo-vtv9.png',
    url: 'https://vtv9.vtv.vn/vtv9hd.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'htv7-hd',
    name: 'HTV7 HD',
    logo: 'https://upload.wikimedia.org/wikipedia/vi/a/a2/HTV7_logo_2016.png',
    url: 'https://live.htv.com.vn/live/htv7.m3u8',
    group: 'HTV & Miền Nam',
  },
  {
    id: 'htv9-hd',
    name: 'HTV9 HD',
    logo: 'https://upload.wikimedia.org/wikipedia/vi/6/6f/HTV9_logo_2016.png',
    url: 'https://live.htv.com.vn/live/htv9.m3u8',
    group: 'HTV & Miền Nam',
  },
  {
    id: 'htv-the-thao',
    name: 'HTV Thể Thao',
    logo: 'https://upload.wikimedia.org/wikipedia/vi/8/8c/HTV_The_Thao_logo_2013.png',
    url: 'https://live.htv.com.vn/live/htv_the_thao.m3u8',
    group: 'Thể Thao & Bóng Đá',
  },
  {
    id: 'vtc1-hd',
    name: 'VTC1 HD (Tin tức)',
    logo: 'https://upload.wikimedia.org/wikipedia/vi/9/93/VTC1_2017.png',
    url: 'https://vtc.gov.vn/live/vtc1.m3u8',
    group: 'VTC & Tin Tức',
  },
  {
    id: 'vtc3-hd',
    name: 'VTC3 HD (Thể thao)',
    logo: 'https://upload.wikimedia.org/wikipedia/vi/4/46/VTC3_2017.png',
    url: 'https://vtc.gov.vn/live/vtc3.m3u8',
    group: 'Thể Thao & Bóng Đá',
  },
];

let cachedChannels = [];
let lastFetchTime = 0;
const CACHE_TTL_MS = 6 * 3600 * 1000; // 6 hours

function ensureUploadDir() {
  if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  }
}

function loadConfig() {
  ensureUploadDir();
  const defaultConfig = {
    sourceType: 'default',
    sourceUrl: DEFAULT_SOURCE_URL,
    uploadedFile: '',
    playlists: [
      {
        id: 'pl-default',
        name: 'Kênh Quốc Gia (iptv-org)',
        type: 'url',
        url: DEFAULT_SOURCE_URL,
        enabled: true,
      }
    ],
    hiddenChannelIds: [],
    pinnedChannelIds: ['vtv1-hd', 'vtv3-hd', 'htv-the-thao', 'vtc3-hd'],
    lastUpdated: new Date().toISOString(),
  };

  if (!fs.existsSync(CONFIG_PATH)) {
    saveConfig(defaultConfig);
    return defaultConfig;
  }

  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf-8');
    const parsed = JSON.parse(raw);
    const cfg = { ...defaultConfig, ...parsed };

    // Migration: populate playlists if empty or not array
    if (!Array.isArray(cfg.playlists) || cfg.playlists.length === 0) {
      cfg.playlists = [];
      if (cfg.sourceType === 'file' && cfg.uploadedFile) {
        cfg.playlists.push({
          id: 'pl-file-1',
          name: 'File Playlist M3U',
          type: 'file',
          file: cfg.uploadedFile,
          enabled: true,
        });
      } else if (cfg.sourceType === 'url' && cfg.sourceUrl && cfg.sourceUrl !== DEFAULT_SOURCE_URL) {
        cfg.playlists.push({
          id: 'pl-url-1',
          name: 'Playlist URL Tùy Chỉnh',
          type: 'url',
          url: cfg.sourceUrl,
          enabled: true,
        });
      }

      if (cfg.playlists.length === 0) {
        cfg.playlists.push({
          id: 'pl-default',
          name: 'Kênh Quốc Gia (iptv-org)',
          type: 'url',
          url: DEFAULT_SOURCE_URL,
          enabled: true,
        });
      }
    }

    return cfg;
  } catch (err) {
    console.error('[IPTV Service] Error reading iptv_config.json:', err.message);
    return defaultConfig;
  }
}

function saveConfig(cfg) {
  try {
    cfg.lastUpdated = new Date().toISOString();
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf-8');
    return true;
  } catch (err) {
    console.error('[IPTV Service] Error saving iptv_config.json:', err.message);
    return false;
  }
}

/**
 * Robust M3U / Extended M3U Parser
 * Parses #EXTINF attributes: tvg-id, tvg-name, tvg-logo, group-title, http-user-agent, http-referrer
 */
function parseM3U(content) {
  if (!content || typeof content !== 'string') return [];

  const lines = content.split(/\r?\n/);
  const channels = [];
  let curMeta = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    if (line.startsWith('#EXTINF:')) {
      curMeta = {
        name: '',
        logo: '',
        group: 'Khác',
        tvgId: '',
        headers: {},
      };

      // Extract attributes: key="value" or key=value
      const attrRegex = /([a-zA-Z0-9_-]+)=(?:"([^"]*)"|'([^']*)'|([^,\s]+))/g;
      let match;
      while ((match = attrRegex.exec(line)) !== null) {
        const key = match[1].toLowerCase();
        const val = match[2] || match[3] || match[4] || '';

        if (key === 'tvg-logo' || key === 'logo') {
          curMeta.logo = val;
        } else if (key === 'tvg-name' || key === 'name') {
          curMeta.name = val;
        } else if (key === 'group-title' || key === 'group') {
          curMeta.group = val;
        } else if (key === 'tvg-id' || key === 'id') {
          curMeta.tvgId = val;
        } else if (key === 'http-user-agent' || key === 'user-agent') {
          curMeta.headers['User-Agent'] = val;
        } else if (key === 'http-referrer' || key === 'referer') {
          curMeta.headers['Referer'] = val;
        }
      }

      // Extract display title after the last comma
      const commaIdx = line.lastIndexOf(',');
      if (commaIdx !== -1) {
        const displayTitle = line.substring(commaIdx + 1).trim();
        if (displayTitle) {
          curMeta.name = displayTitle;
        }
      }

      if (!curMeta.name && curMeta.tvgId) {
        curMeta.name = curMeta.tvgId;
      }
    } else if (line.startsWith('#EXTVLCOPT:') || line.startsWith('#EXTHTTP:')) {
      if (curMeta) {
        if (line.includes('http-user-agent=')) {
          curMeta.headers['User-Agent'] = line.split('http-user-agent=')[1].trim();
        }
        if (line.includes('http-referrer=')) {
          curMeta.headers['Referer'] = line.split('http-referrer=')[1].trim();
        }
      }
    } else if (!line.startsWith('#')) {
      // Stream URL line
      if (line.startsWith('http://') || line.startsWith('https://')) {
        const channelName = curMeta?.name || `Kênh #${channels.length + 1}`;
        const rawGroup = curMeta?.group || 'Kênh Chung';
        const normalizedGroup = normalizeGroupName(rawGroup, channelName);

        const idBase = curMeta?.tvgId || channelName;
        const cleanId = idBase.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '') || `ch-${channels.length + 1}`;

        channels.push({
          id: cleanId,
          name: channelName,
          logo: curMeta?.logo || '',
          url: line,
          group: normalizedGroup,
          headers: curMeta?.headers || {},
        });

        curMeta = null;
      }
    }
  }

  return channels;
}

/**
 * Categorize into clean Vietnamese TV groups
 */
function normalizeGroupName(group, name) {
  const q = `${group} ${name}`.toLowerCase();

  if (q.includes('vtv') || q.includes('quốc gia')) return 'VTV Quốc Gia';
  if (q.includes('htv') || q.includes('thvl') || q.includes('hồ chí minh') || q.includes('sài gòn')) return 'HTV & Miền Nam';
  if (q.includes('vtc') || q.includes('tin tức') || q.includes('news') || q.includes('quốc hội') || q.includes('nhân dân') || q.includes('antv')) return 'VTC & Tin Tức';
  if (q.includes('thể thao') || q.includes('sport') || q.includes('bóng đá') || q.includes('football') || q.includes('k+') || q.includes('on sports')) return 'Thể Thao & Bóng Đá';
  if (q.includes('phim') || q.includes('movie') || q.includes('cinema') || q.includes('hbo') || q.includes('discovery') || q.includes('quốc tế') || q.includes('cartoon') || q.includes('animax')) return 'Phim & Quốc Tế';
  if (q.includes('hà nội') || q.includes('đà nẵng') || q.includes('hải phòng') || q.includes('cần thơ') || q.includes('địa phương') || q.includes('tỉnh')) return 'Kênh Địa Phương';

  return group && group !== 'Khác' ? group : 'Kênh Chung';
}

/**
 * Fetch and parse raw M3U from active sources
 */
async function fetchRawChannels(config) {
  let allChannels = [];
  const playlists = Array.isArray(config.playlists) && config.playlists.length > 0
    ? config.playlists.filter(p => p.enabled !== false)
    : [
        {
          id: 'pl-default',
          name: 'Kênh Quốc Gia (iptv-org)',
          type: config.sourceType === 'file' ? 'file' : 'url',
          url: config.sourceUrl || DEFAULT_SOURCE_URL,
          file: config.uploadedFile,
          enabled: true,
        }
      ];

  for (const pl of playlists) {
    let m3uText = '';
    const plName = pl.name || 'Playlist';
    const plId = pl.id || ('pl-' + Date.now());

    if (pl.type === 'file' && pl.file) {
      const filePath = path.join(UPLOAD_DIR, pl.file);
      if (fs.existsSync(filePath)) {
        try {
          m3uText = fs.readFileSync(filePath, 'utf-8');
        } catch (e) {
          console.error(`[IPTV Service] Error reading file ${pl.file}:`, e.message);
        }
      }
    } else if (pl.url) {
      try {
        console.log(`[IPTV Service] Fetching playlist "${plName}" from ${pl.url}...`);
        const res = await axios.get(pl.url, {
          timeout: 12000,
          headers: {
            'User-Agent': 'Mozilla/5.0 (SmartTV; VolPiMedia/1.0.10)',
            'Accept': '*/*',
          },
        });
        m3uText = typeof res.data === 'string' ? res.data : JSON.stringify(res.data);
      } catch (err) {
        console.error(`[IPTV Service] Failed to fetch M3U from ${pl.url}:`, err.message);
      }
    }

    const channels = parseM3U(m3uText);
    for (const c of channels) {
      // Ensure unique channel id while keeping clean legacy matching
      const uniqueId = plId === 'pl-default' ? c.id : `${plId}_${c.id}`;
      allChannels.push({
        ...c,
        id: uniqueId,
        sourceId: plId,
        sourceName: plName,
      });
    }
  }

  if (allChannels.length === 0) {
    console.log('[IPTV Service] Using fallback verified channels.');
    allChannels = BUILTIN_FALLBACK_CHANNELS.map(c => ({
      ...c,
      sourceId: 'pl-default',
      sourceName: 'Kênh Mặc Định',
    }));
  }

  return allChannels;
}

/**
 * Main function to get channels.
 * forAdmin: true returns all channels with isHidden & isPinned attributes.
 * forAdmin: false (client apps) filters out hidden channels and sorts pinned to the top.
 */
async function getChannels({ forceRefresh = false, forAdmin = false, sourceId = '' } = {}) {
  const config = loadConfig();
  const now = Date.now();

  if (forceRefresh || cachedChannels.length === 0 || now - lastFetchTime > CACHE_TTL_MS) {
    const raw = await fetchRawChannels(config);
    cachedChannels = raw;
    lastFetchTime = now;
  }

  const hiddenSet = new Set(config.hiddenChannelIds || []);
  const pinnedSet = new Set(config.pinnedChannelIds || []);

  const enriched = cachedChannels.map((c) => {
    const rawSuffix = c.id.includes('_') ? c.id.split('_').slice(1).join('_') : c.id;
    const isPinned = pinnedSet.has(c.id) || pinnedSet.has(rawSuffix) || pinnedSet.has(c.url) || pinnedSet.has(c.name);
    const isHidden = hiddenSet.has(c.id) || hiddenSet.has(rawSuffix) || hiddenSet.has(c.url) || hiddenSet.has(c.name);
    return {
      ...c,
      sourceId: c.sourceId || 'pl-default',
      sourceName: c.sourceName || 'Chung',
      isPinned,
      isHidden,
    };
  });

  // Calculate dynamic source statistics
  const sourceStats = new Map();
  sourceStats.set('ALL', { id: 'ALL', name: 'Tất Cả Các Nguồn', count: 0 });
  if (Array.isArray(config.playlists)) {
    config.playlists.forEach((p) => {
      sourceStats.set(p.id, { id: p.id, name: p.name, count: 0, enabled: p.enabled !== false, type: p.type });
    });
  }

  enriched.forEach((c) => {
    if (!c.isHidden) {
      const allItem = sourceStats.get('ALL');
      if (allItem) allItem.count++;
      if (sourceStats.has(c.sourceId)) {
        sourceStats.get(c.sourceId).count++;
      }
    }
  });
  const sources = Array.from(sourceStats.values());

  if (forAdmin) {
    return {
      config,
      sources,
      totalCount: enriched.length,
      channels: enriched,
    };
  }

  // Filter by source if requested
  let visible = enriched.filter((c) => !c.isHidden);
  if (sourceId && sourceId !== 'ALL') {
    visible = visible.filter((c) => c.sourceId === sourceId);
  }

  // Sort: Pinned first (0), then by Name
  visible.sort((a, b) => {
    if (a.isPinned && !b.isPinned) return -1;
    if (!a.isPinned && b.isPinned) return 1;
    return a.name.localeCompare(b.name, 'vi');
  });

  return visible;
}

/**
 * Get sources summary
 */
async function getSources() {
  const config = loadConfig();
  const channels = await getChannels();
  const sourceStats = new Map();
  sourceStats.set('ALL', { id: 'ALL', name: 'Tất Cả Các Nguồn', count: channels.length });

  if (Array.isArray(config.playlists)) {
    config.playlists.forEach((p) => {
      const count = channels.filter(c => c.sourceId === p.id).length;
      sourceStats.set(p.id, { id: p.id, name: p.name, type: p.type, enabled: p.enabled !== false, count });
    });
  }

  return Array.from(sourceStats.values());
}

/**
 * Add a new playlist
 */
function addPlaylist({ name, type = 'url', url = '', content = '', filename = '' }) {
  const config = loadConfig();
  if (!Array.isArray(config.playlists)) config.playlists = [];

  const plId = 'pl-' + Date.now();
  let safeFilename = '';

  if (type === 'file' && content) {
    ensureUploadDir();
    safeFilename = 'playlist_' + Date.now() + '.m3u';
    const targetPath = path.join(UPLOAD_DIR, safeFilename);
    fs.writeFileSync(targetPath, content, 'utf-8');
  }

  const newPl = {
    id: plId,
    name: (name || (type === 'file' ? filename || 'File Playlist' : 'Link IPTV')).trim(),
    type: type === 'file' ? 'file' : 'url',
    url: type === 'url' ? url.trim() : undefined,
    file: type === 'file' ? safeFilename : undefined,
    enabled: true,
    createdAt: new Date().toISOString(),
  };

  config.playlists.push(newPl);
  saveConfig(config);
  clearCache();
  return { success: true, playlist: newPl, config };
}

/**
 * Delete a playlist
 */
function deletePlaylist(id) {
  const config = loadConfig();
  if (!Array.isArray(config.playlists)) return { success: false, error: 'Không có playlist nào' };

  config.playlists = config.playlists.filter(p => p.id !== id);

  // If all playlists deleted, restore default
  if (config.playlists.length === 0) {
    config.playlists.push({
      id: 'pl-default',
      name: 'Kênh Quốc Gia (iptv-org)',
      type: 'url',
      url: DEFAULT_SOURCE_URL,
      enabled: true,
    });
  }

  saveConfig(config);
  clearCache();
  return { success: true, config };
}

/**
 * Toggle enable/disable playlist
 */
function togglePlaylist(id, enabled) {
  const config = loadConfig();
  if (!Array.isArray(config.playlists)) return { success: false, error: 'Không tìm thấy playlist' };

  const pl = config.playlists.find(p => p.id === id);
  if (!pl) return { success: false, error: 'Không tìm thấy playlist ' + id };

  pl.enabled = enabled !== undefined ? Boolean(enabled) : !pl.enabled;
  saveConfig(config);
  clearCache();
  return { success: true, playlist: pl, config };
}

/**
 * Legacy compatibility: Update source configuration
 */
function setSource(type, url) {
  const config = loadConfig();
  config.sourceType = type === 'url' ? 'url' : 'default';
  if (url) {
    config.sourceUrl = url.trim();
    // Also add or update in playlists
    const existing = config.playlists.find(p => p.id === 'pl-url-main');
    if (existing) {
      existing.url = url.trim();
      existing.enabled = true;
    } else {
      config.playlists.push({
        id: 'pl-url-main',
        name: 'Playlist URL Cá Nhân',
        type: 'url',
        url: url.trim(),
        enabled: true,
      });
    }
  } else {
    // default
    const existing = config.playlists.find(p => p.id === 'pl-default');
    if (existing) existing.enabled = true;
  }
  saveConfig(config);
  clearCache();
  return config;
}

/**
 * Legacy compatibility: Upload and set M3U file
 */
function uploadM3uFile(filename, buffer) {
  ensureUploadDir();
  const safeFilename = 'playlist_' + Date.now() + '.m3u';
  const targetPath = path.join(UPLOAD_DIR, safeFilename);

  fs.writeFileSync(targetPath, buffer);

  const config = loadConfig();
  config.sourceType = 'file';
  config.uploadedFile = safeFilename;

  if (!Array.isArray(config.playlists)) config.playlists = [];
  config.playlists.push({
    id: 'pl-file-' + Date.now(),
    name: filename || 'File Playlist M3U',
    type: 'file',
    file: safeFilename,
    enabled: true,
  });

  saveConfig(config);
  clearCache();
  return { success: true, filename: safeFilename, config };
}

/**
 * Save channel pin and hide states from Web Dashboard
 */
function updateChannelSettings({ hiddenChannelIds, pinnedChannelIds }) {
  const config = loadConfig();
  if (Array.isArray(hiddenChannelIds)) config.hiddenChannelIds = hiddenChannelIds;
  if (Array.isArray(pinnedChannelIds)) config.pinnedChannelIds = pinnedChannelIds;
  saveConfig(config);
  return config;
}

/**
 * Force refresh cache immediately
 */
function clearCache() {
  cachedChannels = [];
  lastFetchTime = 0;
}

module.exports = {
  getChannels,
  getSources,
  addPlaylist,
  deletePlaylist,
  togglePlaylist,
  setSource,
  uploadM3uFile,
  updateChannelSettings,
  clearCache,
  loadConfig,
  saveConfig,
  parseM3U,
  DEFAULT_SOURCE_URL,
};

