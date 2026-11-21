const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const AUTH_CONFIG_PATH = path.join(__dirname, '..', 'auth_config.json');
const LOCKOUT_PATH = path.join(__dirname, '..', 'auth_lockouts.json');

// 2-tier Progressive Lockout Configuration
const TIER1_MAX_FAILS = 5;
const TIER1_LOCK_MS = 15 * 60 * 1000; // 15 phút
const TIER2_MAX_FAILS = 10;
const TIER2_LOCK_MS = 24 * 60 * 60 * 1000; // 24 giờ (1 ngày)
const FAILURE_WINDOW_MS = 24 * 60 * 60 * 1000; // Cửa sổ đếm 24h

let cachedAuthConfig = null;
let cachedAuthMtimeMs = 0;

// In-memory + disk-persisted IP lockout map: ip -> { fails, windowStart, lockedUntil }
const loginFailures = new Map();

function atomicWriteJson(filePath, data) {
  const tmpPath = `${filePath}.tmp.${process.pid}.${Date.now()}`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf-8');
  fs.renameSync(tmpPath, filePath);
}

function loadLockouts() {
  try {
    if (fs.existsSync(LOCKOUT_PATH)) {
      const parsed = JSON.parse(fs.readFileSync(LOCKOUT_PATH, 'utf-8'));
      const now = Date.now();
      for (const [ip, rec] of Object.entries(parsed || {})) {
        if (rec && (rec.lockedUntil > now || (now - (rec.windowStart || 0)) < FAILURE_WINDOW_MS)) {
          loginFailures.set(ip, rec);
        }
      }
    }
  } catch (err) {
    console.warn('[AuthService] Could not load auth_lockouts.json:', err.message);
  }
}

function saveLockouts() {
  try {
    const now = Date.now();
    const obj = {};
    for (const [ip, rec] of loginFailures.entries()) {
      if (rec.lockedUntil > now || (now - (rec.windowStart || 0)) < FAILURE_WINDOW_MS) {
        obj[ip] = rec;
      } else {
        loginFailures.delete(ip);
      }
    }
    atomicWriteJson(LOCKOUT_PATH, obj);
  } catch (err) {
    console.warn('[AuthService] Could not save auth_lockouts.json:', err.message);
  }
}

loadLockouts();

function hashPassword(password, salt) {
  return crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
}

function loadAuthConfig() {
  if (!fs.existsSync(AUTH_CONFIG_PATH)) {
    const initUser = (process.env.ADMIN_USER || 'admin').trim();
    const envPass = (process.env.ADMIN_PASSWORD || '').trim();
    const bootstrapPass = envPass || crypto.randomBytes(12).toString('base64url');
    const salt = crypto.randomBytes(16).toString('hex');
    const passwordHash = hashPassword(bootstrapPass, salt);

    const initialConfig = {
      username: initUser,
      salt: salt,
      passwordHash: passwordHash,
      sessions: {},
      createdAt: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
    };

    saveAuthConfig(initialConfig);
    if (!envPass) {
      console.warn(`[AuthService] Initialized auth_config.json for "${initUser}". Generated bootstrap password: ${bootstrapPass}`);
    }
    return initialConfig;
  }

  try {
    const stat = fs.statSync(AUTH_CONFIG_PATH);
    if (cachedAuthConfig && stat.mtimeMs === cachedAuthMtimeMs) {
      return cachedAuthConfig;
    }
    const raw = fs.readFileSync(AUTH_CONFIG_PATH, 'utf-8');
    const parsed = JSON.parse(raw);
    if (!parsed.sessions || typeof parsed.sessions !== 'object') {
      parsed.sessions = {};
    }
    cachedAuthConfig = parsed;
    cachedAuthMtimeMs = stat.mtimeMs;
    return parsed;
  } catch (err) {
    console.error('[AuthService] Error reading auth_config.json:', err.message);
    if (cachedAuthConfig) return cachedAuthConfig;
    return { username: '', salt: '', passwordHash: '', sessions: {} };
  }
}

function saveAuthConfig(config) {
  try {
    config.lastUpdated = new Date().toISOString();
    atomicWriteJson(AUTH_CONFIG_PATH, config);
    cachedAuthConfig = config;
    try {
      cachedAuthMtimeMs = fs.statSync(AUTH_CONFIG_PATH).mtimeMs;
    } catch (_) {}
    return true;
  } catch (err) {
    console.error('[AuthService] Error saving auth_config.json:', err.message);
    return false;
  }
}

function pruneExpiredSessions(config) {
  const now = Date.now();
  let modified = false;
  for (const token in config.sessions) {
    if (!config.sessions[token] || config.sessions[token].expiresAt < now) {
      delete config.sessions[token];
      modified = true;
    }
  }
  return modified;
}

function parseCookies(req) {
  const list = {};
  const rc = req && req.headers ? req.headers.cookie : null;
  if (!rc || typeof rc !== 'string') return list;
  rc.split(';').forEach((cookie) => {
    const idx = cookie.indexOf('=');
    if (idx <= 0) return;
    const key = cookie.slice(0, idx).trim();
    const rawVal = cookie.slice(idx + 1).trim();
    if (!key) return;
    try {
      list[key] = decodeURIComponent(rawVal);
    } catch (_) {
      list[key] = rawVal;
    }
  });
  return list;
}

function extractToken(req) {
  // 1. From HttpOnly Cookie (primary)
  const cookies = parseCookies(req);
  if (cookies['volpi_session']) {
    return cookies['volpi_session'];
  }

  // 2. From Authorization Header
  const authHeader = req.headers['authorization'];
  if (typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7).trim();
  }

  // 3. From x-auth-token Header
  if (typeof req.headers['x-auth-token'] === 'string' && req.headers['x-auth-token'].trim()) {
    return req.headers['x-auth-token'].trim();
  }

  return null;
}

function getClientIp(req) {
  const ip = (req && (req.ip || req.socket?.remoteAddress)) || 'unknown';
  return String(ip).replace(/^::ffff:/, '');
}

function sanitizeRedirect(rawUrl) {
  if (typeof rawUrl !== 'string') return '/';
  const trimmed = rawUrl.trim();
  // Only allow safe local paths like / or /iptv?x=1 (block //evil.com, http://, javascript:)
  if (/^\/(?!\/)/.test(trimmed)) {
    return trimmed;
  }
  return '/';
}

function formatDurationVietnamese(seconds) {
  if (seconds >= 3600) {
    const h = Math.floor(seconds / 3600);
    const m = Math.ceil((seconds % 3600) / 60);
    return m > 0 ? `${h} giờ ${m} phút` : `${h} giờ`;
  }
  if (seconds >= 60) {
    const m = Math.ceil(seconds / 60);
    return `${m} phút`;
  }
  return `${Math.max(1, seconds)} giây`;
}

function checkLoginLockout(ip) {
  if (!ip) return { locked: false };
  const rec = loginFailures.get(ip);
  if (!rec) return { locked: false };
  const now = Date.now();
  if (rec.lockedUntil && rec.lockedUntil > now) {
    const retryAfterSeconds = Math.ceil((rec.lockedUntil - now) / 1000);
    return {
      locked: true,
      retryAfterSeconds,
      fails: rec.fails,
      error: `IP tạm bị khóa do nhập sai quá nhiều lần. Vui lòng thử lại sau ${formatDurationVietnamese(retryAfterSeconds)}.`,
    };
  }
  // Reset window if 24h passed
  if (now - (rec.windowStart || 0) >= FAILURE_WINDOW_MS) {
    loginFailures.delete(ip);
    saveLockouts();
  }
  return { locked: false };
}

function recordLoginFailure(ip) {
  if (!ip) return { locked: false, remainingAttempts: TIER1_MAX_FAILS };
  const now = Date.now();
  let rec = loginFailures.get(ip);
  if (!rec || now - (rec.windowStart || 0) >= FAILURE_WINDOW_MS) {
    rec = { fails: 0, windowStart: now, lockedUntil: 0 };
  }
  rec.fails += 1;

  let locked = false;
  let retryAfterSeconds = 0;

  if (rec.fails >= TIER2_MAX_FAILS) {
    rec.lockedUntil = now + TIER2_LOCK_MS;
    locked = true;
    retryAfterSeconds = Math.ceil(TIER2_LOCK_MS / 1000);
    console.warn(`[AuthService] IP ${ip} hit ${rec.fails} failed logins -> locked for 24h.`);
  } else if (rec.fails >= TIER1_MAX_FAILS && rec.fails % TIER1_MAX_FAILS === 0) {
    rec.lockedUntil = now + TIER1_LOCK_MS;
    locked = true;
    retryAfterSeconds = Math.ceil(TIER1_LOCK_MS / 1000);
    console.warn(`[AuthService] IP ${ip} hit ${rec.fails} failed logins -> locked for 15m.`);
  }

  loginFailures.set(ip, rec);
  saveLockouts();

  const nextThreshold = rec.fails < TIER1_MAX_FAILS ? TIER1_MAX_FAILS : TIER2_MAX_FAILS;
  const remainingAttempts = Math.max(0, nextThreshold - rec.fails);
  return { locked, retryAfterSeconds, fails: rec.fails, remainingAttempts };
}

function clearLoginFailure(ip) {
  if (ip && loginFailures.has(ip)) {
    loginFailures.delete(ip);
    saveLockouts();
  }
}

function validateCredentials(username, password) {
  const config = loadAuthConfig();
  if (!config || !config.username || !config.salt || !config.passwordHash) {
    return false;
  }

  const cleanUser = (typeof username === 'string' ? username : '').trim().toLowerCase();
  const expectedUser = String(config.username).trim().toLowerCase();
  if (!cleanUser || cleanUser !== expectedUser) {
    return false;
  }

  const cleanPass = (typeof password === 'string' ? password : '').trim();
  if (!cleanPass) return false;

  try {
    const computed = hashPassword(cleanPass, config.salt);
    const a = Buffer.from(computed, 'utf8');
    const b = Buffer.from(String(config.passwordHash), 'utf8');
    if (a.length === b.length && crypto.timingSafeEqual(a, b)) {
      return true;
    }
  } catch (_) {}

  return false;
}

function login(username, password, rememberMe = true, ip = null) {
  const lockState = checkLoginLockout(ip);
  if (lockState.locked) {
    return {
      success: false,
      locked: true,
      retryAfterSeconds: lockState.retryAfterSeconds,
      error: lockState.error,
    };
  }

  if (!validateCredentials(username, password)) {
    const failState = recordLoginFailure(ip);
    if (failState.locked) {
      return {
        success: false,
        locked: true,
        retryAfterSeconds: failState.retryAfterSeconds,
        error: `Bạn đã nhập sai ${failState.fails} lần. IP bị tạm khóa trong ${formatDurationVietnamese(failState.retryAfterSeconds)}.`,
      };
    }
    return {
      success: false,
      locked: false,
      remainingAttempts: failState.remainingAttempts,
      error: `Tên đăng nhập hoặc mật khẩu không đúng (còn ${failState.remainingAttempts} lần thử trước khi tạm khóa).`,
    };
  }

  clearLoginFailure(ip);

  const config = loadAuthConfig();
  pruneExpiredSessions(config);

  const token = crypto.randomBytes(32).toString('hex');
  const durationMs = rememberMe ? 30 * 24 * 3600 * 1000 : 24 * 3600 * 1000;
  const maxAgeSeconds = Math.floor(durationMs / 1000);
  const expiresAt = Date.now() + durationMs;

  config.sessions[token] = {
    username: config.username,
    createdAt: Date.now(),
    expiresAt: expiresAt,
  };

  saveAuthConfig(config);

  return {
    success: true,
    token,
    username: config.username,
    expiresAt,
    maxAgeSeconds,
  };
}

function logout(token) {
  if (!token) return { success: true };
  const config = loadAuthConfig();
  if (config.sessions[token]) {
    delete config.sessions[token];
    saveAuthConfig(config);
  }
  return { success: true };
}

function validateSession(token) {
  if (!token || typeof token !== 'string') return null;
  const config = loadAuthConfig();
  const session = config.sessions[token];
  if (!session) return null;

  if (session.expiresAt < Date.now()) {
    delete config.sessions[token];
    saveAuthConfig(config);
    return null;
  }

  return session;
}

function changePassword(username, currentPassword, newPassword) {
  if (!validateCredentials(username, currentPassword)) {
    return { success: false, error: 'Mật khẩu hiện tại không đúng' };
  }

  if (!newPassword || typeof newPassword !== 'string' || newPassword.trim().length < 6) {
    return { success: false, error: 'Mật khẩu mới phải có ít nhất 6 ký tự' };
  }

  const config = loadAuthConfig();
  const newSalt = crypto.randomBytes(16).toString('hex');
  const newHash = hashPassword(newPassword.trim(), newSalt);

  config.salt = newSalt;
  config.passwordHash = newHash;
  // Remove legacy backup pin fields if present
  delete config.pinSalt;
  delete config.pinHash;

  // Prune all sessions to force re-login for security
  config.sessions = {};
  saveAuthConfig(config);

  return { success: true, message: 'Đổi mật khẩu thành công! Vui lòng đăng nhập lại.' };
}

/**
 * Express Middleware: Require Authentication for web pages and admin APIs
 */
function requireAuth(req, res, next) {
  const token = extractToken(req);
  const session = validateSession(token);

  if (session) {
    req.user = session;
    return next();
  }

  const isHtmlRequest = (req.headers.accept && req.headers.accept.includes('text/html')) ||
                        req.path === '/' ||
                        req.path === '/index.html' ||
                        req.path === '/admin' ||
                        req.path === '/config' ||
                        req.path === '/iptv' ||
                        req.path === '/iptv.html' ||
                        req.path === '/gdrive' ||
                        req.path === '/gdrive.html' ||
                        req.path === '/telegram' ||
                        req.path === '/telegram.html';

  if (isHtmlRequest) {
    const returnUrl = encodeURIComponent(sanitizeRedirect(req.originalUrl || '/'));
    return res.redirect(`/login?redirect=${returnUrl}`);
  }

  return res.status(401).json({
    success: false,
    error: 'Vui lòng đăng nhập để truy cập tài nguyên này',
    code: 'UNAUTHORIZED',
  });
}

function optionalAuth(req, res, next) {
  const token = extractToken(req);
  const session = validateSession(token);
  if (session) {
    req.user = session;
  }
  next();
}

module.exports = {
  loadAuthConfig,
  saveAuthConfig,
  hashPassword,
  validateCredentials,
  login,
  logout,
  validateSession,
  changePassword,
  extractToken,
  parseCookies,
  getClientIp,
  sanitizeRedirect,
  checkLoginLockout,
  recordLoginFailure,
  clearLoginFailure,
  requireAuth,
  optionalAuth,
};
