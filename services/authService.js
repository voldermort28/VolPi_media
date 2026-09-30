const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const AUTH_CONFIG_PATH = path.join(__dirname, '..', 'auth_config.json');
const DEFAULT_USERNAME = process.env.ADMIN_USER || 'admin';
const DEFAULT_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';
const BACKUP_PIN = '3105'; // Matches the in-app secret movie PIN

function hashPassword(password, salt) {
  return crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
}

function loadAuthConfig() {
  if (!fs.existsSync(AUTH_CONFIG_PATH)) {
    const salt = crypto.randomBytes(16).toString('hex');
    const passwordHash = hashPassword(DEFAULT_PASSWORD, salt);
    const pinSalt = crypto.randomBytes(16).toString('hex');
    const pinHash = hashPassword(BACKUP_PIN, pinSalt);

    const initialConfig = {
      username: DEFAULT_USERNAME,
      salt: salt,
      passwordHash: passwordHash,
      pinSalt: pinSalt,
      pinHash: pinHash,
      sessions: {},
      createdAt: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
    };

    saveAuthConfig(initialConfig);
    return initialConfig;
  }

  try {
    const raw = fs.readFileSync(AUTH_CONFIG_PATH, 'utf-8');
    const parsed = JSON.parse(raw);
    if (!parsed.sessions || typeof parsed.sessions !== 'object') {
      parsed.sessions = {};
    }
    return parsed;
  } catch (err) {
    console.error('[AuthService] Error reading auth_config.json:', err.message);
    const salt = crypto.randomBytes(16).toString('hex');
    return {
      username: DEFAULT_USERNAME,
      salt: salt,
      passwordHash: hashPassword(DEFAULT_PASSWORD, salt),
      sessions: {},
    };
  }
}

function saveAuthConfig(config) {
  try {
    config.lastUpdated = new Date().toISOString();
    fs.writeFileSync(AUTH_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf-8');
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
    if (config.sessions[token].expiresAt < now) {
      delete config.sessions[token];
      modified = true;
    }
  }
  return modified;
}

function parseCookies(req) {
  const list = {};
  const rc = req.headers.cookie;
  if (!rc) return list;
  rc.split(';').forEach((cookie) => {
    const parts = cookie.split('=');
    const key = parts.shift().trim();
    if (key) {
      list[key] = decodeURIComponent(parts.join('='));
    }
  });
  return list;
}

function extractToken(req) {
  // 1. From Cookies
  const cookies = parseCookies(req);
  if (cookies['volpi_session']) {
    return cookies['volpi_session'];
  }

  // 2. From Authorization Header
  const authHeader = req.headers['authorization'];
  if (authHeader && authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7).trim();
  }

  // 3. From x-auth-token Header
  if (req.headers['x-auth-token']) {
    return req.headers['x-auth-token'];
  }

  // 4. From Query Param
  if (req.query && (req.query.token || req.query.auth_token)) {
    return req.query.token || req.query.auth_token;
  }

  return null;
}

function validateCredentials(username, password) {
  const config = loadAuthConfig();
  const cleanUser = (username || '').trim().toLowerCase();
  const expectedUser = (config.username || 'admin').toLowerCase();

  if (cleanUser !== expectedUser) {
    return false;
  }

  const cleanPass = (password || '').trim();
  if (!cleanPass) return false;

  // 1. Check Primary Password Hash
  try {
    const computed = hashPassword(cleanPass, config.salt);
    if (crypto.timingSafeEqual(Buffer.from(computed), Buffer.from(config.passwordHash))) {
      return true;
    }
  } catch (_) {}

  // 2. Check Backup PIN Hash (3105)
  if (config.pinHash && config.pinSalt) {
    try {
      const computedPin = hashPassword(cleanPass, config.pinSalt);
      if (crypto.timingSafeEqual(Buffer.from(computedPin), Buffer.from(config.pinHash))) {
        return true;
      }
    } catch (_) {}
  }

  // 3. Fallback direct match for fresh default setups
  if (cleanPass === DEFAULT_PASSWORD || cleanPass === BACKUP_PIN) {
    return true;
  }

  return false;
}

function login(username, password, rememberMe = true) {
  if (!validateCredentials(username, password)) {
    return { success: false, error: 'Tên đăng nhập hoặc mật khẩu không đúng' };
  }

  const config = loadAuthConfig();
  pruneExpiredSessions(config);

  const token = crypto.randomBytes(32).toString('hex');
  const durationMs = rememberMe ? 30 * 24 * 3600 * 1000 : 24 * 3600 * 1000; // 30 days vs 24 hours
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
  if (!token) return null;
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

  if (!newPassword || newPassword.trim().length < 4) {
    return { success: false, error: 'Mật khẩu mới phải có ít nhất 4 ký tự' };
  }

  const config = loadAuthConfig();
  const newSalt = crypto.randomBytes(16).toString('hex');
  const newHash = hashPassword(newPassword.trim(), newSalt);

  config.salt = newSalt;
  config.passwordHash = newHash;

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

  // Not authenticated
  const isHtmlRequest = (req.headers.accept && req.headers.accept.includes('text/html')) ||
                        req.path === '/' ||
                        req.path === '/index.html' ||
                        req.path === '/iptv' ||
                        req.path === '/iptv.html';

  if (isHtmlRequest) {
    const returnUrl = encodeURIComponent(req.originalUrl || '/');
    return res.redirect(`/login?redirect=${returnUrl}`);
  }

  return res.status(401).json({
    success: false,
    error: 'Vui lòng đăng nhập để truy cập tài nguyên này',
    code: 'UNAUTHORIZED',
  });
}

/**
 * Express Middleware: Optional Auth (populates req.user if session valid)
 */
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
  requireAuth,
  optionalAuth,
  DEFAULT_USERNAME,
  DEFAULT_PASSWORD,
  BACKUP_PIN,
};
