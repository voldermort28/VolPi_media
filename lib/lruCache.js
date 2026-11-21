/**
 * Bounded LRU + optional TTL Map-compatible cache.
 * Prevents unbounded memory growth on long-running Node.js / PM2 processes.
 */
class LruTtlCache {
  constructor({ maxEntries = 200, ttlMs = 0 } = {}) {
    this.maxEntries = maxEntries;
    this.ttlMs = ttlMs;
    this._map = new Map();
  }

  get size() {
    return this._map.size;
  }

  has(key) {
    if (!this._map.has(key)) return false;
    if (this.ttlMs > 0) {
      const entry = this._map.get(key);
      if (Date.now() - entry.createdAt > this.ttlMs) {
        this._map.delete(key);
        return false;
      }
    }
    return true;
  }

  get(key) {
    if (!this._map.has(key)) return undefined;
    const entry = this._map.get(key);
    if (this.ttlMs > 0 && Date.now() - entry.createdAt > this.ttlMs) {
      this._map.delete(key);
      return undefined;
    }
    // Refresh recency (move to end)
    this._map.delete(key);
    this._map.set(key, entry);
    return entry.value;
  }

  set(key, value) {
    if (this._map.has(key)) {
      this._map.delete(key);
    }
    this._map.set(key, { value, createdAt: Date.now() });
    while (this._map.size > this.maxEntries) {
      const oldestKey = this._map.keys().next().value;
      this._map.delete(oldestKey);
    }
    return this;
  }

  delete(key) {
    return this._map.delete(key);
  }

  clear() {
    this._map.clear();
  }

  *keys() {
    for (const k of this._map.keys()) {
      yield k;
    }
  }

  *values() {
    for (const entry of this._map.values()) {
      yield entry.value;
    }
  }

  *entries() {
    for (const [k, entry] of this._map.entries()) {
      yield [k, entry.value];
    }
  }

  [Symbol.iterator]() {
    return this.entries();
  }
}

module.exports = { LruTtlCache };
