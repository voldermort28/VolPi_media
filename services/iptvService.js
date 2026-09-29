const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const axios = require('axios');

const CONFIG_PATH = path.join(__dirname, '..', 'iptv_config.json');
const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');

// Default reliable Vietnam IPTV source (tested daily with GitHub Actions, fast FPT Play/Viettel CDN)
const DEFAULT_SOURCE_URL = 'https://raw.githubusercontent.com/khanh71/All-In-One-IPTV/main/http-iptv.m3u';

// Built-in verified backup channels with direct CDN access
const BUILTIN_FALLBACK_CHANNELS = [
  {
    id: 'vtv1-hd',
    name: 'VTV1 HD',
    logo: 'https://i.postimg.cc/F1FvzstX/V1.png',
    url: 'https://live.fptplay53.net/live/media/vtv1/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv2-hd',
    name: 'VTV2 HD',
    logo: 'https://i.postimg.cc/yDR4tDRm/V2.png',
    url: 'https://live.fptplay53.net/live/media/vtv2/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv3-hd',
    name: 'VTV3 HD',
    logo: 'https://i.postimg.cc/B8cWZRM0/V3.png',
    url: 'https://live.fptplay53.net/live/media/vtv3/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv4-hd',
    name: 'VTV4 HD',
    logo: 'https://i.postimg.cc/Wqzxnzj0/V4.png',
    url: 'https://live.fptplay53.net/live/media/vtv4/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv5-hd',
    name: 'VTV5 HD',
    logo: 'https://i.postimg.cc/ZC91vWVM/V5.png',
    url: 'https://live.fptplay53.net/live/media/vtv5/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv7-hd',
    name: 'VTV7 HD',
    logo: 'https://i.postimg.cc/ykSbYwN8/V7.png',
    url: 'https://live.fptplay53.net/live/media/vtv7/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv8-hd',
    name: 'VTV8 HD',
    logo: 'https://i.postimg.cc/k2QYWK8w/V8.png',
    url: 'https://live.fptplay53.net/fnxhd1/vtv8hd_vhls.smil/chunklist_b5000000.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'vtv9-hd',
    name: 'VTV9 HD',
    logo: 'https://i.postimg.cc/phT0NSS6/V9.png',
    url: 'https://live.fptplay53.net/live/media/vtv9/live247-hls-avc/index.m3u8',
    group: 'VTV Quốc Gia',
  },
  {
    id: 'htv7-hd',
    name: 'HTV7 HD',
    logo: 'https://i.imgur.com/n2PEK28.png',
    url: 'https://live.fptplay53.net/epzhd1/htv7hd_vhls.smil/chunklist_b5000000.m3u8',
    group: 'HTV & Miền Nam',
  },
  {
    id: 'htv9-hd',
    name: 'HTV9 HD',
    logo: 'https://i.imgur.com/6GSN524.png',
    url: 'https://live.fptplay53.net/epzhd1/htv9hd_vhls.smil/chunklist_b5000000.m3u8',
    group: 'HTV & Miền Nam',
  },
  {
    id: 'vinhlong1-hd',
    name: 'Vĩnh Long 1 HD',
    logo: 'https://i.imgur.com/q3fjpYc.png',
    url: 'https://live.fptplay53.net/epzhd2/vinhlong1_vhls.smil/chunklist_b5000000.m3u8',
    group: 'Đài Địa Phương',
  },
  {
    id: 'vinhlong2-hd',
    name: 'Vĩnh Long 2 HD',
    logo: 'https://i.imgur.com/zGv54Ed.png',
    url: 'https://live.fptplay53.net/epzhd2/vinhlong2_vhls.smil/chunklist_b5000000.m3u8',
    group: 'Đài Địa Phương',
  },
  {
    id: 'vinhlong3-hd',
    name: 'Vĩnh Long 3 HD',
    logo: 'https://i.imgur.com/44c1Yoz.png',
    url: 'https://live.fptplay53.net/epzhd2/vinhlong3_vhls.smil/chunklist_b5000000.m3u8',
    group: 'Đài Địa Phương',
  },
  {
    id: 'vinhlong4-hd',
    name: 'Vĩnh Long 4 HD',
    logo: 'https://i.imgur.com/JWDsJxB.png',
    url: 'https://live.fptplay53.net/epzhd2/vinhlong4-hd_vhls.smil/chunklist_b5000000.m3u8',
    group: 'Đài Địa Phương',
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
      cfg.playlists.push({
        id: 'pl-default',
        name: 'Kênh Quốc Gia (iptv-org)',
        type: 'url',
        url: DEFAULT_SOURCE_URL,
        enabled: true,
      });

      if (cfg.uploadedFile) {
        cfg.playlists.push({
          id: 'pl-file-1',
          name: 'File Playlist M3U',
          type: 'file',
          file: cfg.uploadedFile,
          enabled: true,
        });
      }

      if (cfg.sourceUrl && cfg.sourceUrl !== DEFAULT_SOURCE_URL) {
        cfg.playlists.push({
          id: 'pl-url-user',
          name: 'Bóng Đá Trực Tiếp (THTT)',
          type: 'url',
          url: cfg.sourceUrl,
          enabled: true,
        });
      }

      saveConfig(cfg);
    }

    // Auto-upgrade obsolete/broken iptv-org playlist to high-speed FPT/Viettel CDN All-In-One-IPTV
    const defPl = (cfg.playlists || []).find(p => p.id === 'pl-default');
    if (defPl && defPl.url && defPl.url.includes('iptv-org.github.io/iptv/countries/vn.m3u')) {
      console.log('[IPTV Service] Upgrading default playlist to All-In-One-IPTV (FPT/Viettel CDN)');
      defPl.url = DEFAULT_SOURCE_URL;
      defPl.name = 'Kênh Quốc Gia & Địa Phương (FPT/Viettel CDN)';
      saveConfig(cfg);
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
  const usedIds = new Set();
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
        } else if (key === 'http-referrer' || key === 'referrer' || key === 'referer' || key === 'http-referer') {
          curMeta.headers['Referer'] = val;
        } else if (key === 'http-origin' || key === 'origin') {
          curMeta.headers['Origin'] = val;
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
        if (line.startsWith('#EXTHTTP:')) {
          try {
            const jsonStr = line.substring(9).trim();
            const parsed = JSON.parse(jsonStr);
            Object.assign(curMeta.headers, parsed);
          } catch (e) {}
        }
        const opt = line.substring(line.indexOf(':') + 1).trim();
        const eqIdx = opt.indexOf('=');
        if (eqIdx !== -1) {
          const k = opt.substring(0, eqIdx).toLowerCase();
          const v = opt.substring(eqIdx + 1).trim();
          if (k === 'http-referrer' || k === 'referrer' || k === 'referer' || k === 'http-referer') {
            curMeta.headers['Referer'] = v;
          } else if (k === 'http-user-agent' || k === 'user-agent') {
            curMeta.headers['User-Agent'] = v;
          } else if (k === 'http-origin' || k === 'origin') {
            curMeta.headers['Origin'] = v;
          }
        }
      }
    } else if (!line.startsWith('#')) {
      // Stream URL line
      if (line.startsWith('http://') || line.startsWith('https://')) {
        let streamUrl = line;
        const headers = curMeta?.headers ? { ...curMeta.headers } : {};

        // Parse inline pipe parameters: url|Referer=...&User-Agent=...
        if (streamUrl.includes('|')) {
          const pipeParts = streamUrl.split('|');
          streamUrl = pipeParts[0].trim();
          const paramStr = pipeParts.slice(1).join('|').trim();
          const pairs = paramStr.split('&');
          for (const pair of pairs) {
            const eq = pair.indexOf('=');
            if (eq !== -1) {
              const pk = pair.substring(0, eq).trim();
              const pv = pair.substring(eq + 1).trim();
              if (pk.toLowerCase() === 'referer' || pk.toLowerCase() === 'referrer') {
                headers['Referer'] = pv;
              } else if (pk.toLowerCase() === 'user-agent') {
                headers['User-Agent'] = pv;
              } else {
                headers[pk] = pv;
              }
            }
          }
        }

        const channelName = curMeta?.name || `Kênh #${channels.length + 1}`;
        const rawGroup = curMeta?.group || 'Kênh Chung';
        const normalizedGroup = normalizeGroupName(rawGroup, channelName);

        const idBase = curMeta?.tvgId || channelName;
        const cleanId = idBase.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '') || `ch-${channels.length + 1}`;
        
        let uniqueId = cleanId;
        let counter = 1;
        while (usedIds.has(uniqueId)) {
          uniqueId = `${cleanId}-${counter++}`;
        }
        usedIds.add(uniqueId);

        const ref = headers['Referer'] || headers['referer'] || '';
        const ua = headers['User-Agent'] || headers['user-agent'] || '';
        const proxyUrl = `/api/iptv/stream-proxy?url=${encodeURIComponent(streamUrl)}${ref ? `&ref=${encodeURIComponent(ref)}` : ''}${ua ? `&ua=${encodeURIComponent(ua)}` : ''}`;

        channels.push({
          id: uniqueId,
          name: channelName,
          logo: curMeta?.logo || '',
          url: streamUrl,
          proxyUrl: proxyUrl,
          group: normalizedGroup,
          headers: headers,
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
          name: 'Kênh Quốc Gia & Địa Phương',
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

  const cleanUrl = (url || '').trim();
  const cleanName = (name || '').trim();

  // If url already exists in playlists, update/enable it
  if (type === 'url' && cleanUrl) {
    const existing = config.playlists.find(p => p.type === 'url' && p.url === cleanUrl);
    if (existing) {
      if (cleanName) existing.name = cleanName;
      existing.enabled = true;
      saveConfig(config);
      clearCache();
      return { success: true, playlist: existing, config, updated: true };
    }
  }

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
    name: cleanName || (type === 'file' ? filename || 'File Playlist' : 'Link IPTV'),
    type: type === 'file' ? 'file' : 'url',
    url: type === 'url' ? cleanUrl : undefined,
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
      name: 'Kênh Quốc Gia & Địa Phương',
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

/**
 * Stream Proxy to bypass CORS & Referer restrictions on Web & Smart TV
 * Rewrites .m3u8 playlists so all sub-manifests and chunks stream through this proxy.
 * Binary segments (.ts, .aac, .mp4) are piped directly with CORS and upstream headers.
 */
async function handleStreamProxy(req, res) {
  // Always attach CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');

  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }

  const targetUrl = req.query.url;
  if (!targetUrl || (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://'))) {
    return res.status(400).send('Invalid or missing stream URL parameter');
  }

  const referer = req.query.ref || '';
  const userAgent = req.query.ua || '';

  const upstreamHeaders = {
    'User-Agent': userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Encoding': 'identity', // Ensure plain text m3u8 so we can rewrite without gzip decoding
  };

  if (referer) {
    upstreamHeaders['Referer'] = referer;
    try {
      upstreamHeaders['Origin'] = new URL(referer).origin;
    } catch (_) {}
  }

  if (req.headers['range']) {
    upstreamHeaders['Range'] = req.headers['range'];
  }

  try {
    const upstreamRes = await axios({
      method: req.method === 'HEAD' ? 'HEAD' : 'GET',
      url: targetUrl,
      headers: upstreamHeaders,
      responseType: 'stream',
      timeout: 15000,
      validateStatus: () => true,
      maxRedirects: 5,
    });

    if (upstreamRes.status >= 400) {
      res.status(upstreamRes.status);
      return upstreamRes.data.pipe(res);
    }

    const finalUrl = upstreamRes.request?.res?.responseUrl || targetUrl;
    const contentType = (upstreamRes.headers['content-type'] || '').toLowerCase();
    const contentEncoding = (upstreamRes.headers['content-encoding'] || '').toLowerCase();
    const isM3u8 = targetUrl.toLowerCase().includes('.m3u8') ||
                   targetUrl.toLowerCase().includes('.m3u') ||
                   finalUrl.toLowerCase().includes('.m3u8') ||
                   finalUrl.toLowerCase().includes('.m3u') ||
                   contentType.includes('mpegurl') ||
                   contentType.includes('application/x-mpegurl') ||
                   contentType.includes('text/plain') ||
                   contentType.includes('application/vnd.apple.mpegurl');

    if (isM3u8 && req.method !== 'HEAD') {
      const chunks = [];
      for await (const chunk of upstreamRes.data) {
        chunks.push(chunk);
      }
      const buffer = Buffer.concat(chunks);
      let rawText = '';
      if (contentEncoding === 'gzip') {
        try {
          rawText = zlib.gunzipSync(buffer).toString('utf-8');
        } catch (_) {
          rawText = buffer.toString('utf-8');
        }
      } else if (contentEncoding === 'deflate') {
        try {
          rawText = zlib.inflateSync(buffer).toString('utf-8');
        } catch (_) {
          rawText = buffer.toString('utf-8');
        }
      } else if (contentEncoding === 'br') {
        try {
          rawText = zlib.brotliDecompressSync(buffer).toString('utf-8');
        } catch (_) {
          rawText = buffer.toString('utf-8');
        }
      } else {
        rawText = buffer.toString('utf-8');
      }

      if (rawText.includes('#EXTM3U')) {
        const rewritten = rewriteM3u8Content(rawText, finalUrl, referer, userAgent);

        res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
        return res.status(upstreamRes.status).send(rewritten);
      } else {
        res.setHeader('Content-Type', contentType || 'text/plain');
        return res.status(upstreamRes.status).send(rawText);
      }
    }

    // Binary stream chunk (.ts, AAC, audio/video)
    res.setHeader('Content-Type', contentType || 'video/MP2T');
    if (upstreamRes.headers['content-length']) {
      res.setHeader('Content-Length', upstreamRes.headers['content-length']);
    }
    if (upstreamRes.headers['content-range']) {
      res.setHeader('Content-Range', upstreamRes.headers['content-range']);
    }
    if (upstreamRes.headers['accept-ranges']) {
      res.setHeader('Accept-Ranges', upstreamRes.headers['accept-ranges']);
    }
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.status(upstreamRes.status);

    upstreamRes.data.on('error', (err) => {
      console.error('[Stream Proxy Stream Error]:', err.message);
      if (!res.headersSent) res.status(502).end();
    });

    upstreamRes.data.pipe(res);
  } catch (err) {
    console.error(`[Stream Proxy Error for ${targetUrl}]:`, err.message);
    if (!res.headersSent) {
      res.status(502).send('Error proxying stream: ' + err.message);
    }
  }
}

/**
 * Rewrites URLs in M3U8 content to route child manifests, audio/sub renditions, encryption keys, and segments back through stream-proxy
 */
function rewriteM3u8Content(m3u8Text, baseUrl, referer, userAgent) {
  const lines = m3u8Text.split(/\r?\n/);
  const output = [];

  for (let line of lines) {
    const trimmed = line.trim();
    if (!trimmed) {
      output.push(line);
      continue;
    }

    // Rewrite tags containing URI (e.g. #EXT-X-MEDIA, #EXT-X-KEY, #EXT-X-MAP, #EXT-X-PART, #EXT-X-PRELOAD-HINT)
    if (trimmed.startsWith('#')) {
      if (trimmed.includes('URI=')) {
        const rewritten = line.replace(/URI=(?:"([^"]+)"|([^\s,]+))/g, (match, quotedUri, unquotedUri) => {
          const rawUri = quotedUri || unquotedUri;
          if (!rawUri) return match;
          try {
            const absUrl = new URL(rawUri, baseUrl).href;
            const proxied = `/api/iptv/stream-proxy?url=${encodeURIComponent(absUrl)}${referer ? `&ref=${encodeURIComponent(referer)}` : ''}${userAgent ? `&ua=${encodeURIComponent(userAgent)}` : ''}`;
            return `URI="${proxied}"`;
          } catch (e) {
            return match;
          }
        });
        output.push(rewritten);
      } else {
        output.push(line);
      }
      continue;
    }

    // Media segment or sub-manifest URI
    try {
      const absUrl = new URL(trimmed, baseUrl).href;
      const proxied = `/api/iptv/stream-proxy?url=${encodeURIComponent(absUrl)}${referer ? `&ref=${encodeURIComponent(referer)}` : ''}${userAgent ? `&ua=${encodeURIComponent(userAgent)}` : ''}`;
      output.push(proxied);
    } catch (e) {
      output.push(line);
    }
  }

  return output.join('\n');
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
  handleStreamProxy,
  DEFAULT_SOURCE_URL,
};

