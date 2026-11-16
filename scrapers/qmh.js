const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().qmhBaseUrl || 'https://qmhphimsex.com';
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

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const client = axios.create({
  headers: {
    'User-Agent': USER_AGENT,
    'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
  },
  timeout: 10000,
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
  'phim-sex-viet-nam': 'phim-sex-viet-nam',
  'clip-sex': 'clip-sex',
  'phim-sex-gai-xinh': 'phim-sex-gai-xinh',
  'phim-sex-hoc-sinh': 'phim-sex-hoc-sinh',
  'phim-sex-khong-che': 'phim-sex-khong-che',
  'phim-sex-nhat-ban': 'phim-sex-nhat-ban',
  'phim-sex-vietsub': 'phim-sex-vietsub',
  'phim-sex-vung-trom': 'phim-sex-vung-trom',
  'phim-sex-loan-luan': 'phim-sex-loan-luan',
  'phim-sex-chau-au': 'phim-sex-chau-au',
  'phim-sex-trung-quoc': 'phim-sex-trung-quoc',
  'phim-sex-han-quoc': 'phim-sex-han-quoc',
  'vlxx': 'vlxx',
  'xnxx': 'xnxx',
  'xvideos': 'xvideos',
};

const videoInfoCache = new Map();
const manifestUrlCache = new Map();
const videoDetailsCache = new Map();

function parseVideoItem($, el) {
  const $el = $(el);
  let linkEl = $el.is('a.clip-link') ? $el : $el.find('a.clip-link').first();
  if (!linkEl.length) {
    linkEl = $el.find('a').first();
  }

  let rawId = linkEl.attr('data-id') || '';
  if (!rawId) {
    const postContainer = $el.closest('.post, .item-video');
    const postId = postContainer.attr('id') || $el.attr('id') || '';
    const m = postId.match(/post-(\d+)/);
    if (m) rawId = m[1];
  }

  const href = linkEl.attr('href') || '';
  if (!rawId && href) {
    const m2 = href.match(/[?&]p=(\d+)/);
    if (m2) rawId = m2[1];
  }

  if (!rawId) return null;

  const title = linkEl.attr('title') ||
    $el.find('.entry-title a').text().trim() ||
    $el.find('img').attr('alt') ||
    `Video ${rawId}`;

  const poster = $el.find('img').attr('src') ||
    $el.find('img').attr('data-src') ||
    $el.find('img').attr('data-original') ||
    '';

  const views = $el.find('.views .count').text().trim() || '';
  const likes = $el.find('.likes .count').text().trim() || '';
  const ribbon = views ? `${views} lượt xem` : (likes ? `${likes} thích` : '');

  const item = {
    id: `qmh:${rawId}`,
    rawId: String(rawId),
    title,
    poster,
    href,
    ribbon,
  };

  if (videoInfoCache.size >= 1000 && !videoInfoCache.has(String(rawId))) {
    videoInfoCache.delete(videoInfoCache.keys().next().value);
  }
  videoInfoCache.set(String(rawId), item);
  return item;
}

async function getLatest(page = 1, category = '') {
  let path = '/';
  const catSlug = CATEGORY_MAP[category] || category;

  if (catSlug && catSlug !== 'all' && catSlug !== 'tat-ca') {
    path = page === 1 ? `/${catSlug}/` : `/${catSlug}/page/${page}/`;
  } else {
    path = page === 1 ? '/' : `/page/${page}/`;
  }

  try {
    const res = await client.get(path);
    const $ = cheerio.load(res.data);
    const videos = [];
    const seen = new Set();

    $('.item-video, .item.cf.item-video, .clip-link').each((_, el) => {
      const item = parseVideoItem($, el);
      if (item && !seen.has(item.rawId)) {
        seen.add(item.rawId);
        videos.push(item);
      }
    });

    return videos;
  } catch (err) {
    console.error(`QMH getLatest error (page: ${page}):`, err.message);
    return [];
  }
}

async function search(query, page = 1) {
  if (!query || !query.trim()) return [];

  const encoded = encodeURIComponent(query.trim());
  const path = page === 1 ? `/?s=${encoded}` : `/page/${page}/?s=${encoded}`;

  try {
    const res = await client.get(path);
    const $ = cheerio.load(res.data);
    const videos = [];
    const seen = new Set();

    $('.item-video, .item.cf.item-video, .clip-link').each((_, el) => {
      const item = parseVideoItem($, el);
      if (item && !seen.has(item.rawId)) {
        seen.add(item.rawId);
        videos.push(item);
      }
    });

    return videos;
  } catch (err) {
    console.error(`QMH search error for "${query}":`, err.message);
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
    const targetUrl = info && info.href ? info.href : `/?p=${rawId}`;

    const res = await client.get(targetUrl, {
      maxRedirects: 5,
    });
    const $ = cheerio.load(res.data);

    const title = $('h1.entry-title').text().trim() ||
      $('h2.siteheading a').text().trim() ||
      $('h1').text().trim() ||
      (info ? info.title : `Video ${rawId}`);

    const description = $('.entry-content p').first().text().trim() ||
      $('.entry-summary').text().trim() ||
      '';

    const poster = info && info.poster ? info.poster :
      $('meta[property="og:image"]').attr('content') ||
      $('.entry-content img').first().attr('src') ||
      '';

    const genres = [];
    $('.entry-tags a, .tag-link, .entry-categories a').each((_, el) => {
      const g = $(el).text().trim();
      if (g && !genres.includes(g)) genres.push(g);
    });

    let iframeSrc = '';
    const iframeEl = $('.screen iframe, .fluid-width-video-wrapper iframe, iframe[src*="streamvl"], iframe').first();
    if (iframeEl.length) {
      iframeSrc = iframeEl.attr('src') || iframeEl.attr('data-src') || '';
    }

    const details = {
      id: `qmh:${rawId}`,
      rawId: String(rawId),
      name: title,
      poster,
      background: poster,
      description,
      genres,
      iframeSrc,
      type: 'movie',
    };

    if (videoDetailsCache.size >= 500 && !videoDetailsCache.has(String(rawId))) {
      videoDetailsCache.delete(videoDetailsCache.keys().next().value);
    }
    videoDetailsCache.set(String(rawId), { data: details, time: Date.now() });
    return details;
  } catch (err) {
    console.error(`QMH getVideoDetails error for ${rawId}:`, err.message);
    return {
      id: `qmh:${rawId}`,
      rawId: String(rawId),
      name: `Video ${rawId}`,
      poster: '',
      genres: [],
      iframeSrc: '',
      type: 'movie',
    };
  }
}

async function getRawManifestUrl(rawId) {
  const cached = manifestUrlCache.get(String(rawId));
  if (cached && Date.now() - cached.time < 3600000) {
    return cached.data;
  }

  try {
    const details = await getVideoDetails(rawId);
    if (!details || !details.iframeSrc) {
      return null;
    }

    let iframeUrl = details.iframeSrc;
    if (iframeUrl.startsWith('//')) {
      iframeUrl = 'https:' + iframeUrl;
    }

    const iframeRes = await axios.get(iframeUrl, {
      headers: {
        'Referer': getBaseUrl() + '/',
        'User-Agent': USER_AGENT,
      },
      timeout: 10000,
    });

    const html = typeof iframeRes.data === 'string' ? iframeRes.data : '';
    const match = html.match(/["']file["']\s*:\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/i) ||
      html.match(/file\s*:\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/i);

    if (match && match[1]) {
      const iframeOrigin = new URL(iframeUrl).origin;
      const streamUrl = new URL(match[1], iframeOrigin).toString();
      const result = {
        url: streamUrl,
        referer: iframeOrigin + '/',
      };
      if (manifestUrlCache.size >= 500 && !manifestUrlCache.has(String(rawId))) {
        manifestUrlCache.delete(manifestUrlCache.keys().next().value);
      }
      manifestUrlCache.set(String(rawId), { data: result, time: Date.now() });
      return result;
    }
  } catch (err) {
    console.error(`QMH getRawManifestUrl error (id: ${rawId}):`, err.message);
  }

  return null;
}

async function getVideoInfo(rawId) {
  if (videoInfoCache.has(String(rawId))) {
    return videoInfoCache.get(String(rawId));
  }
  try {
    const details = await getVideoDetails(rawId);
    const info = {
      id: `qmh:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || '',
      ribbon: '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `qmh:${rawId}`,
      rawId: String(rawId),
      title: `Video ${rawId}`,
      poster: '',
      ribbon: '',
    };
  }
}

function clearCache() {
  videoInfoCache.clear();
  manifestUrlCache.clear();
  videoDetailsCache.clear();
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
