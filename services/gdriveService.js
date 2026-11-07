const fs = require('fs');
const path = require('path');
const axios = require('axios');

const CONFIG_PATH = path.join(__dirname, '..', 'gdrive_config.json');

// Memory Cache with 10-minute TTL
const folderCache = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000;

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = fs.readFileSync(CONFIG_PATH, 'utf-8');
      const parsed = JSON.parse(raw);
      if (!parsed.sources) parsed.sources = [];
      if (!parsed.oauth) {
        parsed.oauth = {
          connected: false,
          email: null,
          clientId: '',
          clientSecret: '',
          refreshToken: '',
          accessToken: '',
          tokenExpiry: 0,
        };
      }
      return parsed;
    }
  } catch (e) {
    console.error('[GDriveService] Error loading config:', e.message);
  }
  return {
    oauth: {
      connected: false,
      email: null,
      clientId: '',
      clientSecret: '',
      refreshToken: '',
      accessToken: '',
      tokenExpiry: 0,
    },
    sources: [],
  };
}

function saveConfig(cfg) {
  try {
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf-8');
    return true;
  } catch (e) {
    console.error('[GDriveService] Error saving config:', e.message);
    return false;
  }
}

/**
 * Extracts Google Drive Folder ID from standard links or raw ID
 */
function extractFolderId(input) {
  if (!input) return null;
  const str = input.trim();

  // Pattern: /folders/([a-zA-Z0-9_-]+)
  const folderMatch = str.match(/\/folders\/([a-zA-Z0-9_-]+)/);
  if (folderMatch && folderMatch[1]) return folderMatch[1];

  // Pattern: id=([a-zA-Z0-9_-]+)
  const idMatch = str.match(/[?&]id=([a-zA-Z0-9_-]+)/);
  if (idMatch && idMatch[1]) return idMatch[1];

  // Pattern: /d/([a-zA-Z0-9_-]+)
  const dMatch = str.match(/\/d\/([a-zA-Z0-9_-]+)/);
  if (dMatch && dMatch[1]) return dMatch[1];

  // Raw alphanumeric ID (typically 25-45 chars)
  if (/^[a-zA-Z0-9_-]{15,60}$/.test(str)) {
    return str;
  }

  return null;
}

/**
 * Format bytes to readable size
 */
function formatBytes(bytes) {
  if (!bytes || isNaN(bytes) || bytes <= 0) return '';
  const num = parseInt(bytes, 10);
  if (num < 1024) return `${num} B`;
  if (num < 1024 * 1024) return `${(num / 1024).toFixed(1)} KB`;
  if (num < 1024 * 1024 * 1024) return `${(num / (1024 * 1024)).toFixed(1)} MB`;
  return `${(num / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/**
 * Check if file is a video by extension or mimeType
 */
const VIDEO_EXTENSIONS = ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.ts', '.m4v', '.flv'];
const SUBTITLE_EXTENSIONS = ['.srt', '.vtt', '.ass'];

function isVideoFile(name, mimeType = '') {
  if (mimeType && mimeType.startsWith('video/')) return true;
  if (!name) return false;
  const lower = name.toLowerCase();
  return VIDEO_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

function isSubtitleFile(name, mimeType = '') {
  if (mimeType && (mimeType.includes('subrip') || mimeType.includes('vtt') || mimeType.includes('subtitle'))) return true;
  if (!name) return false;
  const lower = name.toLowerCase();
  return SUBTITLE_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

// =========================================================================
// OAUTH2 TOKEN MANAGEMENT
// =========================================================================

function getOAuthStatus() {
  const cfg = loadConfig();
  const oauth = cfg.oauth || {};
  return {
    connected: !!oauth.connected && !!oauth.refreshToken,
    email: oauth.email || null,
    hasCredentials: !!(oauth.clientId && oauth.clientSecret),
    clientId: oauth.clientId ? `${oauth.clientId.substring(0, 15)}...` : '',
  };
}

function setOAuthCredentials(clientId, clientSecret) {
  const cfg = loadConfig();
  cfg.oauth.clientId = (clientId || '').trim();
  cfg.oauth.clientSecret = (clientSecret || '').trim();
  saveConfig(cfg);
  return { success: true };
}

function getOAuthUrl(redirectUri) {
  const cfg = loadConfig();
  const clientId = cfg.oauth.clientId;
  if (!clientId) {
    throw new Error('Vui lòng cấu hình Google OAuth Client ID trước');
  }

  const scopes = [
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/userinfo.email',
  ].join(' ');

  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: scopes,
    access_type: 'offline',
    prompt: 'consent',
  });

  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

async function handleOAuthCallback(code, redirectUri) {
  const cfg = loadConfig();
  const { clientId, clientSecret } = cfg.oauth;

  if (!clientId || !clientSecret) {
    throw new Error('Thiếu Google OAuth Client ID hoặc Client Secret');
  }

  const tokenRes = await axios.post(
    'https://oauth2.googleapis.com/token',
    new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }).toString(),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      timeout: 10000,
    }
  );

  const { access_token, refresh_token, expires_in } = tokenRes.data;
  let userEmail = null;

  try {
    const userRes = await axios.get('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${access_token}` },
      timeout: 8000,
    });
    userEmail = userRes.data.email;
  } catch (e) {
    console.warn('[GDriveService] Could not fetch user email:', e.message);
  }

  cfg.oauth.connected = true;
  cfg.oauth.email = userEmail || 'Connected Account';
  if (refresh_token) {
    cfg.oauth.refreshToken = refresh_token;
  }
  cfg.oauth.accessToken = access_token;
  cfg.oauth.tokenExpiry = Date.now() + (expires_in ? (expires_in - 120) * 1000 : 3500 * 1000);

  saveConfig(cfg);
  return { success: true, email: cfg.oauth.email };
}

function disconnectOAuth() {
  const cfg = loadConfig();
  cfg.oauth.connected = false;
  cfg.oauth.email = null;
  cfg.oauth.refreshToken = '';
  cfg.oauth.accessToken = '';
  cfg.oauth.tokenExpiry = 0;
  saveConfig(cfg);
  return { success: true };
}

async function getValidAccessToken() {
  const cfg = loadConfig();
  const oauth = cfg.oauth || {};

  if (!oauth.connected || !oauth.refreshToken) {
    return null;
  }

  // If token is still valid (with 60s buffer)
  if (oauth.accessToken && oauth.tokenExpiry && Date.now() < oauth.tokenExpiry) {
    return oauth.accessToken;
  }

  // Refresh token
  try {
    const res = await axios.post(
      'https://oauth2.googleapis.com/token',
      new URLSearchParams({
        client_id: oauth.clientId,
        client_secret: oauth.clientSecret,
        refresh_token: oauth.refreshToken,
        grant_type: 'refresh_token',
      }).toString(),
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: 10000,
      }
    );

    const { access_token, expires_in } = res.data;
    cfg.oauth.accessToken = access_token;
    cfg.oauth.tokenExpiry = Date.now() + (expires_in ? (expires_in - 120) * 1000 : 3500 * 1000);
    saveConfig(cfg);
    return access_token;
  } catch (err) {
    console.error('[GDriveService] Error refreshing access token:', err.response?.data || err.message);
    return null;
  }
}

// =========================================================================
// SOURCES MANAGEMENT
// =========================================================================

async function getSources() {
  const cfg = loadConfig();
  const sources = cfg.sources || [];

  return sources.map((s) => ({
    id: s.id,
    name: s.name,
    folderId: s.folderId,
    url: s.url,
    enabled: s.enabled !== false,
    isPrivate: !!s.isPrivate,
    count: s.lastCount || 0,
    createdAt: s.createdAt || null,
  }));
}

async function addSource({ name, url, isPrivate = false }) {
  const cleanName = (name || '').trim();
  const cleanUrl = (url || '').trim();

  if (!cleanUrl) {
    return { success: false, error: 'Vui lòng nhập đường link hoặc ID thư mục Google Drive' };
  }

  const folderId = extractFolderId(cleanUrl);
  if (!folderId) {
    return { success: false, error: 'Đường dẫn hoặc ID thư mục Google Drive không hợp lệ' };
  }

  const cfg = loadConfig();
  if (!Array.isArray(cfg.sources)) cfg.sources = [];

  // Check duplicate folderId
  const existing = cfg.sources.find((s) => s.folderId === folderId);
  if (existing) {
    return { success: false, error: `Thư mục này đã tồn tại trong danh sách: "${existing.name}"` };
  }

  // Pre-test folder contents to verify
  let count = 0;
  try {
    const contents = await getFolderContents(folderId, { forceRefresh: true });
    count = contents.totalVideos > 0
        ? contents.totalVideos
        : ((contents.videos ? contents.videos.length : 0) + (contents.folders ? contents.folders.length : 0));
  } catch (err) {
    console.warn(`[GDriveService] Warning during test scan of ${folderId}:`, err.message);
  }

  const newSource = {
    id: `gdrive_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
    name: cleanName || 'Thư mục Google Drive',
    folderId,
    url: cleanUrl,
    isPrivate: !!isPrivate,
    enabled: true,
    lastCount: count,
    createdAt: new Date().toISOString(),
  };

  cfg.sources.push(newSource);
  saveConfig(cfg);

  return { success: true, source: newSource, count };
}

function deleteSource(id) {
  const cfg = loadConfig();
  if (!Array.isArray(cfg.sources)) return { success: true };

  const initialLen = cfg.sources.length;
  cfg.sources = cfg.sources.filter((s) => s.id !== id && s.folderId !== id);

  if (cfg.sources.length !== initialLen) {
    saveConfig(cfg);
  }
  return { success: true };
}

function toggleSource(id, enabled) {
  const cfg = loadConfig();
  if (!Array.isArray(cfg.sources)) return { success: false, error: 'Chưa có cấu hình' };

  const source = cfg.sources.find((s) => s.id === id || s.folderId === id);
  if (!source) return { success: false, error: 'Không tìm thấy nguồn' };

  source.enabled = enabled !== false;
  saveConfig(cfg);
  return { success: true, source };
}

// =========================================================================
// FOLDER CONTENTS EXPLORER & PUBLIC SCRAPING
// =========================================================================

/**
 * Fetch folder contents via Google Drive API v3 (using OAuth Bearer token)
 */
async function fetchViaApi(folderId, accessToken) {
  const url = 'https://www.googleapis.com/drive/v3/files';
  const query = `'${folderId}' in parents and trashed = false`;

  const res = await axios.get(url, {
    params: {
      q: query,
      fields: 'files(id, name, mimeType, size, thumbnailLink, modifiedTime, iconLink)',
      pageSize: 1000,
      orderBy: 'folder,name',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    },
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
    timeout: 12000,
  });

  return res.data.files || [];
}

/**
 * Fetch public folder contents by parsing Google Drive web HTML initial data
 */
async function fetchViaPublicWeb(folderId) {
  const url = `https://drive.google.com/drive/folders/${folderId}`;
  try {
    const res = await axios.get(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
      },
      timeout: 10000,
    });

    const html = res.data;
    const files = [];

    // Match _DRIVE_ivd data or embedded JSON arrays in script tags
    // Pattern: window['_DRIVE_ivd'] = '...';
    const match = html.match(/window\['_DRIVE_ivd'\]\s*=\s*'([^']+)'/);
    if (match && match[1]) {
      try {
        const jsonCompat = match[1].replace(/\\x([0-9a-fA-F]{2})/g, '\\u00$1');
        const decoded = JSON.parse(`"${jsonCompat}"`);
        const parsed = JSON.parse(decoded);
        if (Array.isArray(parsed) && Array.isArray(parsed[0])) {
          for (const item of parsed[0]) {
            if (Array.isArray(item) && item[0]) {
              const id = item[0];
              const name = item[2] || 'Tập tin';
              const mimeType = item[3] || '';
              const size = item[13] || item[27] || item[10] || 0;
              files.push({
                id,
                name,
                mimeType,
                size: typeof size === 'number' ? size : 0,
                thumbnailLink: `https://drive.google.com/thumbnail?id=${id}&sz=w400`,
              });
            }
          }
        }
      } catch (err) {
        console.error('[GDriveService] Error decoding _DRIVE_ivd:', err.message);
      }
    }

    // Fallback: match AF_initDataCallback for newer Google Drive web layouts
    if (files.length === 0) {
      const regex = /AF_initDataCallback\s*\(\s*\{[^}]*?data\s*:\s*([\s\S]*?)\s*,\s*sideChannel:/g;
      let m;
      while ((m = regex.exec(html)) !== null) {
        try {
          const parsed = JSON.parse(m[1].trim());
          const walk = (node) => {
            if (!Array.isArray(node)) return;
            if (node.length >= 5 && Array.isArray(node[0]) && typeof node[0][1] === 'string' && node[0][1].length > 20) {
              const id = node[0][1];
              const mimeType = typeof node[4] === 'string' ? node[4] : '';
              let name = 'Tập tin';
              const nodeStr = JSON.stringify(node);
              const nameMatch = nodeStr.match(/\[\[\["([^"]+)",null,1\]\]\]/);
              if (nameMatch) {
                name = nameMatch[1];
              }
              if (id && (mimeType.includes('folder') || mimeType.startsWith('video/') || mimeType.startsWith('audio/'))) {
                files.push({
                  id,
                  name,
                  mimeType,
                  size: 0,
                  thumbnailLink: `https://drive.google.com/thumbnail?id=${id}&sz=w400`,
                });
              }
            }
            for (const child of node) {
              walk(child);
            }
          };
          walk(parsed);
        } catch (_) {}
      }
    }

    // Alternative fallback pattern: search for standard file entries in HTML
    if (files.length === 0) {
      const fileIdRegex = /data-id="([a-zA-Z0-9_-]{20,})"[^>]*data-target="file"/g;
      let m;
      while ((m = fileIdRegex.exec(html)) !== null) {
        files.push({
          id: m[1],
          name: 'Video',
          mimeType: 'video/mp4',
          size: 0,
          thumbnailLink: `https://drive.google.com/thumbnail?id=${m[1]}&sz=w400`,
        });
      }
    }

    return files;
  } catch (err) {
    console.error(`[GDriveService] Public web fetch error for ${folderId}:`, err.message);
    return [];
  }
}

/**
 * Helper to fetch a single folder's raw files
 */
async function fetchFolderItems(folderId, accessToken) {
  let rawFiles = [];
  if (accessToken) {
    try {
      rawFiles = await fetchViaApi(folderId, accessToken);
    } catch (e) {
      console.warn(`[GDriveService] API fetch error for ${folderId}: ${e.message}`);
    }
  }
  if (rawFiles.length === 0) {
    try {
      rawFiles = await fetchViaPublicWeb(folderId);
    } catch (e) {
      console.warn(`[GDriveService] Web fetch error for ${folderId}: ${e.message}`);
    }
  }
  return rawFiles;
}

/**
 * Get folder contents (recursively scans subfolders up to maxDepth)
 */
async function getFolderContents(folderId, { forceRefresh = false, maxDepth = 3 } = {}) {
  const cleanId = extractFolderId(folderId) || folderId;
  const cacheKey = `folder_rec_${cleanId}`;

  // Check cache
  if (!forceRefresh && folderCache.has(cacheKey)) {
    const entry = folderCache.get(cacheKey);
    if (Date.now() - entry.time < CACHE_TTL_MS) {
      return entry.data;
    }
  }

  const accessToken = await getValidAccessToken();

  // BFS Queue to crawl folders
  const queue = [{ id: cleanId, name: 'Thư mục gốc', path: '', depth: 0 }];
  const visited = new Set();

  const directFolders = [];
  const directVideos = [];
  const allFolders = [];
  const allVideos = [];
  const allSubtitles = [];

  while (queue.length > 0) {
    // Process up to 10 folders in parallel
    const batch = queue.splice(0, 10);
    const batchResults = await Promise.all(
      batch.map(async (curr) => {
        if (visited.has(curr.id)) return null;
        visited.add(curr.id);

        const rawFiles = await fetchFolderItems(curr.id, accessToken);
        return { curr, rawFiles };
      })
    );

    for (const res of batchResults) {
      if (!res) continue;
      const { curr, rawFiles } = res;
      const isRoot = curr.id === cleanId;

      for (const f of rawFiles) {
        const isFolder = f.mimeType === 'application/vnd.google-apps.folder';
        const folderPath = curr.path ? `${curr.path} / ${f.name}` : (f.name || '');

        if (isFolder) {
          const folderObj = {
            id: f.id,
            name: f.name || 'Thư mục con',
            isFolder: true,
            mimeType: f.mimeType,
            parentId: curr.id,
            parentName: curr.name,
            folderPath,
          };

          if (isRoot) {
            directFolders.push(folderObj);
          }
          allFolders.push(folderObj);

          if (curr.depth < maxDepth && visited.size < 100) {
            queue.push({
              id: f.id,
              name: f.name || 'Thư mục con',
              path: folderPath,
              depth: curr.depth + 1,
            });
          }
        } else if (isVideoFile(f.name, f.mimeType)) {
          const videoObj = {
            id: f.id,
            name: f.name || 'Video',
            isFolder: false,
            size: parseInt(f.size || 0, 10),
            formattedSize: formatBytes(f.size),
            mimeType: f.mimeType || 'video/mp4',
            thumbnailUrl: f.thumbnailLink || null,
            folderId: curr.id,
            folderName: curr.name,
            folderPath: curr.path || '',
            subtitleFileId: null,
            subtitleName: null,
          };

          if (isRoot) {
            directVideos.push(videoObj);
          }
          allVideos.push(videoObj);
        } else if (isSubtitleFile(f.name, f.mimeType)) {
          allSubtitles.push({
            id: f.id,
            name: f.name,
            folderId: curr.id,
          });
        }
      }
    }
  }

  // Match subtitles with videos
  for (const video of allVideos) {
    const vBase = video.name.substring(0, video.name.lastIndexOf('.')).toLowerCase();
    // Prefer subtitle in the same subfolder
    let matchingSub = allSubtitles.find((s) => {
      if (s.folderId !== video.folderId) return false;
      const sBase = s.name.substring(0, s.name.lastIndexOf('.')).toLowerCase();
      return sBase === vBase || sBase.startsWith(vBase) || vBase.startsWith(sBase);
    });

    if (!matchingSub) {
      matchingSub = allSubtitles.find((s) => {
        const sBase = s.name.substring(0, s.name.lastIndexOf('.')).toLowerCase();
        return sBase === vBase || sBase.startsWith(vBase) || vBase.startsWith(sBase);
      });
    }

    if (matchingSub) {
      video.subtitleFileId = matchingSub.id;
      video.subtitleName = matchingSub.name;
    }
  }

  directFolders.sort((a, b) => a.name.localeCompare(b.name, 'vi', { numeric: true }));
  directVideos.sort((a, b) => a.name.localeCompare(b.name, 'vi', { numeric: true }));
  allVideos.sort((a, b) => {
    if (a.folderPath && b.folderPath && a.folderPath !== b.folderPath) {
      return a.folderPath.localeCompare(b.folderPath, 'vi', { numeric: true });
    }
    return a.name.localeCompare(b.name, 'vi', { numeric: true });
  });

  const result = {
    folderId: cleanId,
    folders: directFolders,
    allFolders,
    videos: directVideos,
    allVideos,
    totalVideos: allVideos.length,
    totalFolders: allFolders.length,
    totalItems: allVideos.length + directFolders.length,
    timestamp: Date.now(),
  };

  // Cache result
  folderCache.set(cacheKey, { time: Date.now(), data: result });

  return result;
}

// =========================================================================
// STREAMING PROXY (HTTP 206 Partial Content Range Support)
// =========================================================================

async function streamVideo(fileId, req, res) {
  const range = req.headers.range;
  const accessToken = await getValidAccessToken();

  let targetUrl = '';
  const requestHeaders = {
    'User-Agent': 'Mozilla/5.0 (SmartTV; VolPiMedia/2.2.20)',
  };

  if (range) {
    requestHeaders['Range'] = range;
  }

  if (accessToken) {
    targetUrl = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`;
    requestHeaders['Authorization'] = `Bearer ${accessToken}`;
  } else {
    // Public download endpoint with virus-scan bypass confirm=t
    targetUrl = `https://drive.usercontent.google.com/download?id=${fileId}&export=download&authuser=0&confirm=t`;
  }

  try {
    const driveRes = await axios.get(targetUrl, {
      headers: requestHeaders,
      responseType: 'stream',
      timeout: 25000,
      maxRedirects: 5,
      validateStatus: (status) => status >= 200 && status < 400,
    });

    const status = driveRes.status === 206 || (range && driveRes.headers['content-range']) ? 206 : 200;

    const responseHeaders = {
      'Accept-Ranges': 'bytes',
      'Content-Type': driveRes.headers['content-type'] || 'video/mp4',
    };

    if (driveRes.headers['content-range']) {
      responseHeaders['Content-Range'] = driveRes.headers['content-range'];
    }
    if (driveRes.headers['content-length']) {
      responseHeaders['Content-Length'] = driveRes.headers['content-length'];
    }

    res.writeHead(status, responseHeaders);
    driveRes.data.pipe(res);

    driveRes.data.on('error', (err) => {
      console.error(`[GDriveStream] Stream error for file ${fileId}:`, err.message);
      if (!res.headersSent) {
        res.status(500).end();
      }
    });

    req.on('close', () => {
      if (driveRes.data && typeof driveRes.data.destroy === 'function') {
        driveRes.data.destroy();
      }
    });
  } catch (err) {
    console.error(`[GDriveStream] Error streaming file ${fileId}:`, err.message);
    if (!res.headersSent) {
      res.status(err.response?.status || 500).json({
        error: 'Không thể phát video từ Google Drive',
        details: err.message,
      });
    }
  }
}

/**
 * Serve subtitle file
 */
async function streamSubtitle(fileId, res) {
  const accessToken = await getValidAccessToken();
  let targetUrl = '';
  const requestHeaders = {};

  if (accessToken) {
    targetUrl = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`;
    requestHeaders['Authorization'] = `Bearer ${accessToken}`;
  } else {
    targetUrl = `https://drive.usercontent.google.com/download?id=${fileId}&export=download&authuser=0&confirm=t`;
  }

  try {
    const subRes = await axios.get(targetUrl, {
      headers: requestHeaders,
      responseType: 'text',
      timeout: 10000,
    });

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.send(subRes.data);
  } catch (e) {
    res.status(404).send('Subtitle not found');
  }
}

module.exports = {
  loadConfig,
  saveConfig,
  extractFolderId,
  getOAuthStatus,
  setOAuthCredentials,
  getOAuthUrl,
  handleOAuthCallback,
  disconnectOAuth,
  getSources,
  addSource,
  deleteSource,
  toggleSource,
  getFolderContents,
  streamVideo,
  streamSubtitle,
};
