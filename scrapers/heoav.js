const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().heoavBaseUrl || 'https://heoav.com';
}

function updateResolvedBaseUrl(url) {
  if (!url) return;
  try {
    const u = new URL(url);
    if (u.origin && u.origin !== 'null' && !u.origin.includes('about:blank')) {
      resolvedBaseUrl = u.origin;
    }
  } catch (e) {}
}

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const client = axios.create({
  headers: {
    'User-Agent': USER_AGENT,
    'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
  },
  timeout: 12000,
  maxRedirects: 5,
});

client.interceptors.request.use((req) => {
  req.baseURL = getBaseUrl();
  return req;
});

client.interceptors.response.use(
  (response) => {
    if (response.request && response.request.res && response.request.res.responseUrl) {
      updateResolvedBaseUrl(response.request.res.responseUrl);
    }
    return response;
  },
  (error) => {
    if (error.response && error.response.request && error.response.request.res && error.response.request.res.responseUrl) {
      updateResolvedBaseUrl(error.response.request.res.responseUrl);
    }
    return Promise.reject(error);
  }
);

const CATEGORY_MAP = {
  'phim-moi': '/phim-moi/',
  'best-of-the-week': '/best-of-the-week/',
  'xem-nhieu': '/xem-nhieu/',
  'thich-nhieu': '/thich-nhieu/',
  'diem-cao': '/diem-cao/',
  'decen-ltx': '/search/decen-ltx/',
  'uncensored': '/search/uncensored/',
  'vietsub': '/search/vietsub/',
  'nu-sinh': '/search/nu-sinh/',
  'gai-xinh': '/search/gai-xinh/',
  'loan-luan': '/search/loan-luan/',
  'vu-to': '/search/vu-to/',
  'len-lut': '/search/len-lut/',
  'threesome': '/search/threesome/',
  'bo-duong': '/search/bo-duong/',
  'thuoc-kich-duc': '/search/thuoc-kich-duc/',
};

const { LruTtlCache } = require("../lib/lruCache");
const videoInfoCache = new LruTtlCache({ maxEntries: 300 });
const manifestUrlCache = new LruTtlCache({ maxEntries: 200 });
const videoDetailsCache = new LruTtlCache({ maxEntries: 300 });
const searchPathCache = new LruTtlCache({ maxEntries: 100 });

function resolveAbsoluteUrl(src) {
  if (!src) return '';
  try {
    return new URL(src, getBaseUrl()).toString();
  } catch (e) {
    return src;
  }
}

function slugifyQuery(text) {
  return String(text || '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function extractRawId(href) {
  if (!href) return '';
  const clean = href.split('?')[0].split('#')[0];
  const m = clean.match(/\/videos\/([^/]+?)(?:\.html)?$/i);
  if (m && m[1]) return m[1];
  return '';
}

function parseVideoItem($, el) {
  const $el = $(el);
  const linkEl = $el.find('a.video-link').first().length
    ? $el.find('a.video-link').first()
    : $el.find('a[href*="/videos/"]').first();

  const href = linkEl.attr('href') || '';
  const rawId = extractRawId(href);
  if (!rawId) return null;

  const title = (
    linkEl.attr('title') ||
    $el.find('.entry-header .title').text() ||
    $el.find('.video-title-link').text() ||
    $el.find('img').attr('alt') ||
    `Video ${rawId}`
  ).trim();

  const rawPoster =
    $el.find('img.video-main-thumb').attr('src') ||
    $el.find('img.video-main-thumb').attr('data-src') ||
    $el.find('img').attr('src') ||
    $el.find('img').attr('data-src') ||
    $el.find('img').attr('data-original') ||
    '';

  const poster = resolveAbsoluteUrl(rawPoster);
  const duration = $el.find('.duration').first().text().trim();
  const views = $el.find('.views').first().text().trim();
  const ribbon = duration || (views ? `${views} views` : '');

  const item = {
    id: `heoav:${rawId}`,
    rawId: String(rawId),
    title,
    poster,
    href: resolveAbsoluteUrl(href),
    ribbon,
  };

  if (videoInfoCache.size >= 1000 && !videoInfoCache.has(String(rawId))) {
    videoInfoCache.delete(videoInfoCache.keys().next().value);
  }
  videoInfoCache.set(String(rawId), item);
  return item;
}

function isPageOutOfRange($, page) {
  if (page <= 1) return false;
  const pag = $('.pagination');
  if (!pag.length) return true;
  const currentText = pag.find('a.current, span.current').first().text().trim();
  if (currentText && parseInt(currentText, 10) !== page) {
    return true;
  }
  return false;
}

function parseListingPage($, page) {
  if (isPageOutOfRange($, page)) {
    return [];
  }

  const videos = [];
  const seen = new Set();

  $('article.thumb-block, article.video-preview-item').each((_, el) => {
    const item = parseVideoItem($, el);
    if (item && !seen.has(item.rawId)) {
      seen.add(item.rawId);
      videos.push(item);
    }
  });

  return videos;
}

async function getLatest(page = 1, category = '') {
  if (page > 1 && category === 'best-of-the-week') {
    return [];
  }

  let basePath = '/phim-moi/';
  if (category && category !== 'all' && category !== 'tat-ca') {
    if (CATEGORY_MAP[category]) {
      basePath = CATEGORY_MAP[category];
    } else if (category.startsWith('/')) {
      basePath = category;
    } else {
      basePath = `/search/${category}/`;
    }
  }

  const reqPath = page > 1 ? `${basePath}?page=${page}` : basePath;

  try {
    const res = await client.get(reqPath);
    const $ = cheerio.load(res.data);
    return parseListingPage($, page);
  } catch (err) {
    console.error(`HeoAV getLatest error (page: ${page}, category: ${category}):`, err.message);
    return [];
  }
}

async function search(query, page = 1) {
  if (!query || !query.trim()) return [];

  const trimmed = query.trim();
  const cacheKey = trimmed.toLowerCase();

  try {
    let reqPath;
    if (page === 1) {
      reqPath = `/?s=${encodeURIComponent(trimmed)}`;
    } else {
      const cachedPath = searchPathCache.get(cacheKey);
      if (cachedPath) {
        reqPath = `${cachedPath}?page=${page}`;
      } else {
        const slug = slugifyQuery(trimmed);
        reqPath = slug ? `/search/${slug}/?page=${page}` : `/?s=${encodeURIComponent(trimmed)}&page=${page}`;
      }
    }

    const res = await client.get(reqPath);

    if (page === 1 && res.request && res.request.res && res.request.res.responseUrl) {
      try {
        const finalUrl = new URL(res.request.res.responseUrl);
        if (finalUrl.pathname && finalUrl.pathname !== '/') {
          if (searchPathCache.size >= 200) {
            searchPathCache.delete(searchPathCache.keys().next().value);
          }
          searchPathCache.set(cacheKey, finalUrl.pathname);
        }
      } catch (e) {}
    }

    const $ = cheerio.load(res.data);
    return parseListingPage($, page);
  } catch (err) {
    console.error(`HeoAV search error for "${query}" (page ${page}):`, err.message);
    return [];
  }
}

async function getVideoDetails(rawId) {
  const cached = videoDetailsCache.get(String(rawId));
  if (cached && Date.now() - cached.time < 1800000) {
    return cached.data;
  }

  try {
    const info = videoInfoCache.get(String(rawId));
    const targetPath = `/videos/${encodeURIComponent(rawId)}.html`;

    const res = await client.get(targetPath, { maxRedirects: 5 });
    const $ = cheerio.load(res.data);

    const title = (
      $('h1').first().text().trim() ||
      $('meta[itemprop="name"]').attr('content') ||
      (info ? info.title : `Video ${rawId}`)
    ).trim();

    const description = (
      $('meta[itemprop="description"]').attr('content') ||
      $('meta[name="description"]').attr('content') ||
      ''
    ).trim();

    const rawPoster =
      (info && info.poster) ||
      $('meta[property="og:image"]').attr('content') ||
      `/poster_thumb/${rawId}.jpg`;
    const poster = resolveAbsoluteUrl(rawPoster);

    const genres = [];
    $('.tags-list a, .video-tags a, .post-tags a').each((_, el) => {
      const g = $(el).text().trim();
      if (g && !genres.includes(g)) genres.push(g);
    });

    const iframeEl = $('#player-frame, .responsive-player iframe, .video-player iframe').first();
    const iframeSrc = resolveAbsoluteUrl(iframeEl.attr('src') || iframeEl.attr('data-src') || '');

    const details = {
      id: `heoav:${rawId}`,
      rawId: String(rawId),
      name: title,
      poster,
      background: poster,
      description,
      genres,
      iframeSrc: iframeSrc || `${getBaseUrl()}/player/?id=${encodeURIComponent(rawId)}`,
      type: 'movie',
    };

    if (videoDetailsCache.size >= 500 && !videoDetailsCache.has(String(rawId))) {
      videoDetailsCache.delete(videoDetailsCache.keys().next().value);
    }
    videoDetailsCache.set(String(rawId), { data: details, time: Date.now() });
    return details;
  } catch (err) {
    console.error(`HeoAV getVideoDetails error for ${rawId}:`, err.message);
    return {
      id: `heoav:${rawId}`,
      rawId: String(rawId),
      name: `Video ${rawId}`,
      poster: resolveAbsoluteUrl(`/poster_thumb/${rawId}.jpg`),
      background: resolveAbsoluteUrl(`/poster_thumb/${rawId}.jpg`),
      description: '',
      genres: [],
      iframeSrc: `${getBaseUrl()}/player/?id=${encodeURIComponent(rawId)}`,
      type: 'movie',
    };
  }
}

async function getRawManifestUrl(rawId) {
  const cached = manifestUrlCache.get(String(rawId));
  if (cached && Date.now() - cached.time < 3600000) {
    return cached.data;
  }

  const baseUrl = getBaseUrl();
  const baseHost = (() => {
    try {
      return new URL(baseUrl).hostname;
    } catch (e) {
      return 'heoav.com';
    }
  })();

  let iframeUrl = `${baseUrl}/player/?id=${encodeURIComponent(rawId)}`;

  try {
    const details = await getVideoDetails(rawId);
    if (details && details.iframeSrc) {
      iframeUrl = details.iframeSrc;
    }
  } catch (e) {}

  try {
    const iframeRes = await axios.get(iframeUrl, {
      headers: {
        'Referer': `${baseUrl}/videos/${encodeURIComponent(rawId)}.html`,
        'User-Agent': USER_AGENT,
      },
      timeout: 12000,
    });

    const html = typeof iframeRes.data === 'string' ? iframeRes.data : '';
    const match =
      html.match(/Promise\.resolve\(\s*["']([^"']+)["']\s*\)/i) ||
      html.match(/["']file["']\s*:\s*["']([^"']+(?:\.m3u8|m3u8\.php)[^"']*)["']/i) ||
      html.match(/file\s*:\s*["']([^"']+(?:\.m3u8|m3u8\.php)[^"']*)["']/i);

    if (match && match[1] && !match[1].includes('deleted') && !match[1].includes('not_available')) {
      const streamUrl = new URL(match[1], iframeUrl).toString();
      const result = {
        url: streamUrl,
        referer: iframeUrl,
      };
      if (manifestUrlCache.size >= 500 && !manifestUrlCache.has(String(rawId))) {
        manifestUrlCache.delete(manifestUrlCache.keys().next().value);
      }
      manifestUrlCache.set(String(rawId), { data: result, time: Date.now() });
      return result;
    }
  } catch (err) {
    console.error(`HeoAV getRawManifestUrl iframe error (id: ${rawId}):`, err.message);
  }

  // Fallback directly to standard HeoAV m3u8 endpoint
  const fallbackUrl = `${baseUrl}/m3u8.php?id=${encodeURIComponent(rawId)}&d=${encodeURIComponent(baseHost)}`;
  const fallbackResult = {
    url: fallbackUrl,
    referer: iframeUrl,
  };
  return fallbackResult;
}

async function getVideoInfo(rawId) {
  if (videoInfoCache.has(String(rawId))) {
    return videoInfoCache.get(String(rawId));
  }
  try {
    const details = await getVideoDetails(rawId);
    const info = {
      id: `heoav:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || resolveAbsoluteUrl(`/poster_thumb/${rawId}.jpg`),
      ribbon: '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `heoav:${rawId}`,
      rawId: String(rawId),
      title: `Video ${rawId}`,
      poster: resolveAbsoluteUrl(`/poster_thumb/${rawId}.jpg`),
      ribbon: '',
    };
  }
}

function clearCache() {
  videoInfoCache.clear();
  manifestUrlCache.clear();
  videoDetailsCache.clear();
  searchPathCache.clear();
  resolvedBaseUrl = null;
}

module.exports = {
  getLatest,
  search,
  getVideoDetails,
  getVideoInfo,
  getRawManifestUrl,
  getBaseUrl,
  clearCache,
  USER_AGENT,
  CATEGORY_MAP,
};
