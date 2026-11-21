const dns = require('dns');
const net = require('net');
const { LruTtlCache } = require('./lruCache');

const dnsCache = new LruTtlCache({ maxEntries: 300, ttlMs: 5 * 60 * 1000 });

function isPrivateIPv4(ip) {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some((n) => isNaN(n) || n < 0 || n > 255)) return true;
  const [a, b] = parts;
  if (a === 0) return true; // 0.0.0.0/8
  if (a === 10) return true; // 10.0.0.0/8
  if (a === 127) return true; // 127.0.0.0/8 loopback
  if (a === 169 && b === 254) return true; // 169.254.0.0/16 link-local / cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a === 192 && b === 168) return true; // 192.168.0.0/16
  if (a === 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
  if (a >= 224) return true; // Multicast & reserved
  return false;
}

function isPrivateIPv6(ip) {
  const lower = ip.toLowerCase();
  if (lower === '::1' || lower === '::' || lower === '0:0:0:0:0:0:0:1') return true;
  if (lower.startsWith('::ffff:')) {
    const v4 = lower.slice(7);
    if (net.isIPv4(v4)) return isPrivateIPv4(v4);
  }
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // ULA fc00::/7
  if (lower.startsWith('fe8') || lower.startsWith('fe9') || lower.startsWith('fea') || lower.startsWith('feb')) {
    return true; // Link-local fe80::/10
  }
  if (lower.startsWith('ff')) return true; // Multicast
  return false;
}

function isPrivateIp(ip) {
  if (!ip) return true;
  if (net.isIPv4(ip)) return isPrivateIPv4(ip);
  if (net.isIPv6(ip)) return isPrivateIPv6(ip);
  return true;
}

/**
 * Validates that a URL is HTTP(S) and does NOT resolve to loopback, private, or cloud metadata IPs.
 * Throws an Error with statusCode=403/400 if unsafe.
 */
async function assertSafeUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || !rawUrl.trim()) {
    const err = new Error('Invalid URL');
    err.statusCode = 400;
    throw err;
  }

  let parsed;
  try {
    parsed = new URL(rawUrl.trim());
  } catch (_) {
    const err = new Error('Malformed URL');
    err.statusCode = 400;
    throw err;
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    const err = new Error('Unsupported URL protocol');
    err.statusCode = 400;
    throw err;
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (
    !hostname ||
    hostname === 'localhost' ||
    hostname.endsWith('.local') ||
    hostname.endsWith('.internal') ||
    hostname === 'metadata.google.internal'
  ) {
    const err = new Error('Blocked internal hostname');
    err.statusCode = 403;
    throw err;
  }

  if (net.isIP(hostname)) {
    if (isPrivateIp(hostname)) {
      const err = new Error('Blocked private IP address');
      err.statusCode = 403;
      throw err;
    }
    return parsed.toString();
  }

  // Resolve DNS (cached 5 min to keep HLS segment proxying fast)
  let addresses = dnsCache.get(hostname);
  if (!addresses) {
    try {
      const resolved = await dns.promises.lookup(hostname, { all: true });
      addresses = resolved.map((r) => r.address);
      dnsCache.set(hostname, addresses);
    } catch (_) {
      const err = new Error('DNS resolution failed');
      err.statusCode = 502;
      throw err;
    }
  }

  if (!addresses || addresses.length === 0 || addresses.some(isPrivateIp)) {
    const err = new Error('Blocked private/internal resolved IP');
    err.statusCode = 403;
    throw err;
  }

  return parsed.toString();
}

module.exports = { assertSafeUrl, isPrivateIp };
