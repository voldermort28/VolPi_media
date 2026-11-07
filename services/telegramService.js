const fs = require('fs');
const path = require('path');
const { TelegramClient, Api } = require('telegram');
const { StringSession } = require('telegram/sessions');

const CONFIG_PATH = path.join(__dirname, '..', 'telegram_config.json');

// Memory Cache with 10-minute TTL for channel video lists
const channelCache = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000;

// Pending login state for phone code verification
let pendingPhoneAuth = null;

// Global singleton Telegram Client instance
let telegramClientInstance = null;

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = fs.readFileSync(CONFIG_PATH, 'utf-8');
      const parsed = JSON.parse(raw);
      if (!parsed.sources) parsed.sources = [];
      if (!parsed.auth) {
        parsed.auth = {
          connected: false,
          type: 'user',
          phoneNumber: null,
          botUsername: null,
          apiId: 2496,
          apiHash: '8da85b0d5b162232e5f22de687712c5b',
          sessionString: '',
        };
      }
      return parsed;
    }
  } catch (e) {
    console.error('[TelegramService] Error loading config:', e.message);
  }
  return {
    auth: {
      connected: false,
      type: 'user',
      phoneNumber: null,
      botUsername: null,
      apiId: 2496,
      apiHash: '8da85b0d5b162232e5f22de687712c5b',
      sessionString: '',
    },
    sources: [],
  };
}

function saveConfig(cfg) {
  try {
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf-8');
    return true;
  } catch (e) {
    console.error('[TelegramService] Error saving config:', e.message);
    return false;
  }
}

/**
 * Extracts standard Channel Identifier from Telegram link or ID
 * e.g.
 * - https://web.telegram.org/a/#-1002117837365 -> -1002117837365
 * - https://web.telegram.org/k/#-1002117837365 -> -1002117837365
 * - https://t.me/c/2117837365/100 -> -1002117837365
 * - https://t.me/mychannel -> @mychannel
 * - -1002117837365 -> -1002117837365
 */
function extractChannelIdentifier(input) {
  if (!input) return null;
  const str = input.trim();

  // Pattern: web.telegram.org/#-100... or /a/#-100... or /k/#-100...
  const webMatch = str.match(/#(-100\d+)/);
  if (webMatch && webMatch[1]) return webMatch[1];

  // Pattern: t.me/c/(\d+) -> -100\d+
  const cMatch = str.match(/t\.me\/c\/(\d+)/);
  if (cMatch && cMatch[1]) {
    return `-100${cMatch[1]}`;
  }

  // Raw channel ID starting with -100
  if (/^-100\d{8,15}$/.test(str)) {
    return str;
  }

  // Numeric channel ID without -100 (e.g. 2117837365)
  if (/^\d{8,15}$/.test(str)) {
    return `-100${str}`;
  }

  // Username: t.me/username
  const usernameMatch = str.match(/t\.me\/([a-zA-Z0-9_]{4,})/);
  if (usernameMatch && usernameMatch[1] && usernameMatch[1] !== 'c') {
    return `@${usernameMatch[1]}`;
  }

  // @username
  if (/^@[a-zA-Z0-9_]{4,}$/.test(str)) {
    return str;
  }

  return str;
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
 * Format duration in seconds to HH:MM:SS or MM:SS
 */
function formatDuration(seconds) {
  if (!seconds || isNaN(seconds) || seconds <= 0) return '';
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) {
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

// =========================================================================
// TELEGRAM CLIENT CONNECTION & AUTH
// =========================================================================

async function getClient() {
  const cfg = loadConfig();
  const { apiId, apiHash, sessionString } = cfg.auth;

  if (telegramClientInstance && telegramClientInstance.connected) {
    return telegramClientInstance;
  }

  const session = new StringSession(sessionString || '');
  const client = new TelegramClient(session, parseInt(apiId, 10), apiHash, {
    connectionRetries: 5,
    useWSS: false,
    autoReconnect: true,
  });

  await client.connect();
  telegramClientInstance = client;
  return client;
}

async function getAuthStatus() {
  const cfg = loadConfig();
  const auth = cfg.auth;

  let isAuthorized = false;
  let meInfo = null;

  if (auth.sessionString) {
    try {
      const client = await getClient();
      isAuthorized = await client.checkAuthorization();
      if (isAuthorized) {
        const me = await client.getMe();
        meInfo = {
          id: me.id ? me.id.toString() : '',
          firstName: me.firstName || '',
          lastName: me.lastName || '',
          username: me.username || null,
          phone: me.phone || auth.phoneNumber || null,
          isBot: !!me.bot,
        };
      }
    } catch (e) {
      console.warn('[TelegramService] Check auth failed:', e.message);
    }
  }

  return {
    connected: isAuthorized,
    type: auth.type || 'user',
    user: meInfo,
    phoneNumber: auth.phoneNumber,
    botUsername: auth.botUsername,
    hasSession: !!auth.sessionString,
  };
}

async function sendPhoneCode(phoneNumber) {
  const cleanPhone = (phoneNumber || '').replace(/[\s-]/g, '');
  if (!cleanPhone.startsWith('+')) {
    throw new Error('Số điện thoại phải có mã quốc gia, ví dụ: +84912345678');
  }

  const cfg = loadConfig();
  const { apiId, apiHash } = cfg.auth;

  const client = await getClient();
  const { phoneCodeHash } = await client.sendCode(
    {
      apiId: parseInt(apiId, 10),
      apiHash,
    },
    cleanPhone
  );

  pendingPhoneAuth = {
    phoneNumber: cleanPhone,
    phoneCodeHash,
    time: Date.now(),
  };

  return {
    success: true,
    phoneNumber: cleanPhone,
    phoneCodeHash,
  };
}

async function signInWithPhoneCode({ phoneNumber, phoneCode, password }) {
  const cleanPhone = (phoneNumber || pendingPhoneAuth?.phoneNumber || '').replace(/[\s-]/g, '');
  const cleanCode = (phoneCode || '').trim();

  if (!cleanPhone || !cleanCode) {
    throw new Error('Thiếu số điện thoại hoặc mã xác thực');
  }

  const phoneCodeHash = pendingPhoneAuth?.phoneCodeHash;
  if (!phoneCodeHash) {
    throw new Error('Phiên xác thực đã hết hạn, vui lòng gửi lại mã OTP');
  }

  const cfg = loadConfig();
  const { apiId, apiHash } = cfg.auth;
  const client = await getClient();

  try {
    await client.invoke(
      new Api.auth.SignIn({
        phoneNumber: cleanPhone,
        phoneCodeHash,
        phoneCode: cleanCode,
      })
    );
  } catch (err) {
    // Check if 2FA password is required
    if (err.message && err.message.includes('SESSION_PASSWORD_NEEDED')) {
      if (!password) {
        return { success: false, needPassword: true, error: 'Tài khoản có bật 2FA, vui lòng nhập Mật Khẩu 2 Bước' };
      }
      const { computeCheck } = require('telegram/Password');
      const passwordResult = await client.invoke(new Api.account.GetPassword());
      const passwordSRP = await computeCheck(passwordResult, password);
      await client.invoke(new Api.auth.CheckPassword({ password: passwordSRP }));
    } else {
      throw err;
    }
  }

  // Save session
  const sessionString = client.session.save();
  cfg.auth.connected = true;
  cfg.auth.type = 'user';
  cfg.auth.phoneNumber = cleanPhone;
  cfg.auth.sessionString = sessionString;
  saveConfig(cfg);
  pendingPhoneAuth = null;

  const me = await client.getMe();
  return {
    success: true,
    user: {
      id: me.id.toString(),
      firstName: me.firstName,
      username: me.username,
    },
  };
}

async function signInWithBot(botToken) {
  const cleanToken = (botToken || '').trim();
  if (!cleanToken) {
    throw new Error('Vui lòng nhập Bot Token từ @BotFather');
  }

  const cfg = loadConfig();
  const { apiId, apiHash } = cfg.auth;

  // Create temporary client for bot
  const session = new StringSession('');
  const client = new TelegramClient(session, parseInt(apiId, 10), apiHash, {
    connectionRetries: 5,
  });

  await client.start({
    botAuthToken: cleanToken,
  });

  const me = await client.getMe();
  const sessionString = client.session.save();

  cfg.auth.connected = true;
  cfg.auth.type = 'bot';
  cfg.auth.botUsername = me.username;
  cfg.auth.sessionString = sessionString;
  saveConfig(cfg);

  telegramClientInstance = client;

  return {
    success: true,
    bot: {
      id: me.id.toString(),
      username: me.username,
      firstName: me.firstName,
    },
  };
}

async function disconnect() {
  const cfg = loadConfig();
  cfg.auth.connected = false;
  cfg.auth.sessionString = '';
  cfg.auth.phoneNumber = null;
  cfg.auth.botUsername = null;
  saveConfig(cfg);

  if (telegramClientInstance) {
    try {
      await telegramClientInstance.disconnect();
    } catch (_) {}
    telegramClientInstance = null;
  }
  return { success: true };
}

// =========================================================================
// SOURCES (CHANNELS / GROUPS) MANAGEMENT
// =========================================================================

async function getSources() {
  const cfg = loadConfig();
  return (cfg.sources || []).map((s) => ({
    id: s.id,
    name: s.name,
    channelId: s.channelId,
    url: s.url,
    enabled: s.enabled !== false,
    count: s.lastCount || 0,
    createdAt: s.createdAt || null,
  }));
}

async function addSource({ name, url }) {
  const cleanUrl = (url || '').trim();
  const channelIdentifier = extractChannelIdentifier(cleanUrl);

  if (!channelIdentifier) {
    return { success: false, error: 'Đường link hoặc ID kênh Telegram không hợp lệ' };
  }

  const cfg = loadConfig();
  if (!Array.isArray(cfg.sources)) cfg.sources = [];

  // Check duplicate
  const existing = cfg.sources.find((s) => s.channelId === channelIdentifier);
  if (existing) {
    return { success: false, error: `Kênh này đã tồn tại trong danh sách: "${existing.name}"` };
  }

  // Pre-test scanning to fetch title and count
  let title = (name || '').trim();
  let count = 0;

  try {
    const scanResult = await getChannelVideos(channelIdentifier, { forceRefresh: true, limit: 50 });
    count = scanResult.videos ? scanResult.videos.length : 0;
    if (!title && scanResult.channelTitle) {
      title = scanResult.channelTitle;
    }
  } catch (err) {
    console.warn(`[TelegramService] Warning during test scan of ${channelIdentifier}:`, err.message);
  }

  const newSource = {
    id: `tg_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
    name: title || channelIdentifier,
    channelId: channelIdentifier,
    url: cleanUrl,
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
  cfg.sources = cfg.sources.filter((s) => s.id !== id && s.channelId !== id);

  if (cfg.sources.length !== initialLen) {
    saveConfig(cfg);
  }
  return { success: true };
}

function toggleSource(id, enabled) {
  const cfg = loadConfig();
  if (!Array.isArray(cfg.sources)) return { success: false, error: 'Chưa có cấu hình' };

  const source = cfg.sources.find((s) => s.id === id || s.channelId === id);
  if (!source) return { success: false, error: 'Không tìm thấy nguồn' };

  source.enabled = enabled !== false;
  saveConfig(cfg);
  return { success: true, source };
}

// =========================================================================
// CHANNEL VIDEO SCANNER & PARSER
// =========================================================================

/**
 * Resolve channel entity
 */
async function resolveChannelEntity(client, channelIdentifier) {
  const idStr = channelIdentifier.toString().trim();

  // If starts with -100
  if (idStr.startsWith('-100')) {
    const rawId = idStr.substring(4);
    try {
      return await client.getEntity(new Api.PeerChannel({ channelId: BigInt(rawId) }));
    } catch (_) {
      try {
        return await client.getInputEntity(BigInt(idStr));
      } catch (__) {
        return await client.getEntity(BigInt(idStr));
      }
    }
  }

  // If username @...
  return await client.getEntity(idStr);
}

/**
 * Fetch and filter video messages from a channel
 */
async function getChannelVideos(channelIdentifier, { forceRefresh = false, limit = 100 } = {}) {
  const channelId = extractChannelIdentifier(channelIdentifier) || channelIdentifier;
  const cacheKey = `tg_videos_${channelId}`;

  // Check cache
  if (!forceRefresh && channelCache.has(cacheKey)) {
    const entry = channelCache.get(cacheKey);
    if (Date.now() - entry.time < CACHE_TTL_MS) {
      return entry.data;
    }
  }

  const client = await getClient();
  const entity = await resolveChannelEntity(client, channelId);

  const channelTitle = entity.title || entity.username || channelId;

  // Get messages
  const messages = await client.getMessages(entity, {
    limit: parseInt(limit, 10) || 100,
  });

  const videos = [];

  for (const msg of messages) {
    if (!msg.media) continue;

    const media = msg.media;
    let document = null;

    if (media.document) {
      document = media.document;
    }

    if (!document) continue;

    // Check if video by mimeType or extension
    const mimeType = document.mimeType || '';
    let fileName = '';
    let duration = 0;
    let width = 0;
    let height = 0;
    let isVideo = mimeType.startsWith('video/');

    if (document.attributes) {
      for (const attr of document.attributes) {
        if (attr.className === 'DocumentAttributeFilename') {
          fileName = attr.fileName || '';
        }
        if (attr.className === 'DocumentAttributeVideo') {
          isVideo = true;
          duration = attr.duration || 0;
          width = attr.w || 0;
          height = attr.h || 0;
        }
      }
    }

    // Check file extension
    const lowerName = fileName.toLowerCase();
    if (!isVideo) {
      if (
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.webm') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.ts') ||
        lowerName.endsWith('.mov')
      ) {
        isVideo = true;
      }
    }

    if (!isVideo) continue;

    // Use message caption or file name as movie title
    let title = (msg.message || '').split('\n')[0].trim();
    if (!title || title.length > 80 || title.startsWith('http')) {
      title = fileName || 'Video';
    }

    const size = parseInt(document.size || 0, 10);
    const hasThumb = !!(document.thumbs && document.thumbs.length > 0);

    videos.push({
      id: msg.id,
      channelId,
      title,
      fileName,
      caption: msg.message || '',
      size,
      formattedSize: formatBytes(size),
      duration,
      formattedDuration: formatDuration(duration),
      width,
      height,
      mimeType: mimeType || 'video/mp4',
      thumbnailUrl: hasThumb ? `/api/telegram/thumb/${encodeURIComponent(channelId)}/${msg.id}` : null,
      date: msg.date ? msg.date * 1000 : Date.now(),
    });
  }

  const result = {
    channelId,
    channelTitle,
    videos,
    total: videos.length,
    timestamp: Date.now(),
  };

  channelCache.set(cacheKey, { time: Date.now(), data: result });
  return result;
}

// =========================================================================
// STREAMING PROXY (HTTP 206 Partial Content Range Support)
// =========================================================================

async function streamMedia(channelIdentifier, messageId, req, res) {
  const channelId = extractChannelIdentifier(channelIdentifier) || channelIdentifier;
  const msgId = parseInt(messageId, 10);

  try {
    const client = await getClient();
    const entity = await resolveChannelEntity(client, channelId);

    const [msg] = await client.getMessages(entity, { ids: [msgId] });
    if (!msg || !msg.media || !msg.media.document) {
      return res.status(404).json({ error: 'Không tìm thấy video trong tin nhắn' });
    }

    const document = msg.media.document;
    const totalSize = parseInt(document.size, 10);
    const mimeType = document.mimeType || 'video/mp4';

    const rangeHeader = req.headers.range;
    let start = 0;
    let end = totalSize - 1;

    // Parse Range header: bytes=start-end
    if (rangeHeader) {
      const parts = rangeHeader.replace(/bytes=/, '').split('-');
      start = parseInt(parts[0], 10);
      if (parts[1]) {
        end = parseInt(parts[1], 10);
      }
    }

    // Limit chunk size per request to 2MB for fast responsive seeking
    const MAX_CHUNK = 2 * 1024 * 1024;
    if (end - start + 1 > MAX_CHUNK) {
      end = start + MAX_CHUNK - 1;
    }
    if (end >= totalSize) {
      end = totalSize - 1;
    }

    const contentLength = end - start + 1;
    const isPartial = !!rangeHeader;

    res.writeHead(isPartial ? 206 : 200, {
      'Content-Range': `bytes ${start}-${end}/${totalSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': contentLength,
      'Content-Type': mimeType,
      'Cache-Control': 'no-cache',
    });

    let isAborted = false;
    req.on('close', () => {
      isAborted = true;
    });

    // Stream chunks via GramJS iterDownload
    for await (const chunk of client.iterDownload({
      file: msg.media,
      offset: BigInt(start),
      limit: contentLength,
      chunkSize: 512 * 1024,
    })) {
      if (isAborted) break;
      res.write(chunk);
    }

    if (!isAborted) {
      res.end();
    }
  } catch (err) {
    console.error(`[TelegramStream] Error streaming msg ${msgId} in ${channelId}:`, err.message);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Lỗi phát video từ Telegram', details: err.message });
    }
  }
}

/**
 * Stream video thumbnail
 */
async function streamThumbnail(channelIdentifier, messageId, res) {
  const channelId = extractChannelIdentifier(channelIdentifier) || channelIdentifier;
  const msgId = parseInt(messageId, 10);

  try {
    const client = await getClient();
    const entity = await resolveChannelEntity(client, channelId);

    const [msg] = await client.getMessages(entity, { ids: [msgId] });
    if (!msg || !msg.media) {
      return res.status(404).send('No thumbnail');
    }

    const buffer = await client.downloadMedia(msg.media, {
      thumb: 1, // small/medium thumbnail
    });

    if (buffer) {
      res.setHeader('Content-Type', 'image/jpeg');
      res.setHeader('Cache-Control', 'public, max-age=86400');
      return res.send(buffer);
    }
    return res.status(404).send('No thumbnail');
  } catch (e) {
    return res.status(404).send('Thumbnail error');
  }
}

module.exports = {
  loadConfig,
  saveConfig,
  extractChannelIdentifier,
  getClient,
  getAuthStatus,
  sendPhoneCode,
  signInWithPhoneCode,
  signInWithBot,
  disconnect,
  getSources,
  addSource,
  deleteSource,
  toggleSource,
  getChannelVideos,
  streamMedia,
  streamThumbnail,
};
