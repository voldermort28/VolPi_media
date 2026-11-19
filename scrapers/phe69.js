const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().phe69BaseUrl || 'https://phe69.shop';
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
  'sex-viet-nam': 'sex-viet-nam',
  'phim-sex-moi': 'phim-sex-moi',
  'phim-sex-sinh-vien': 'phim-sex-sinh-vien',
  'sex-khong-che': 'sex-khong-che',
  'sex-loli-minh-day': 'sex-loli-minh-day',
  'check-hang': 'check-hang',
  'doggy': 'doggy',
  'gai-dam': 'gai-dam',
  'camera': 'camera',
  'bdsm': 'bdsm',
  'may-bay-ba-gia': 'may-bay-ba-gia',
  'jav-hd': 'jav-hd',
};

const videoInfoCache = new Map();
const manifestUrlCache = new Map();
const videoDetailsCache = new Map();

function resolveAbsoluteUrl(src) {
  if (!src) return '';
  try {
    return new URL(src, getBaseUrl()).toString();
  } catch (e) {
    return src;
  }
}

function extractRawId($el, href) {
  let rawId = $el.attr('data-post-id') || $el.attr('data-video-id') || '';

  if (!rawId) {
    const className = $el.attr('class') || '';
    const mClass = className.match(/\bpost-(\d+)\b/);
    if (mClass) rawId = mClass[1];
  }

  if (!rawId) {
    const elId = $el.attr('id') || '';
    const mId = elId.match(/post-(\d+)/);
    if (mId) rawId = mId[1];
  }

  if (!rawId && href) {
    const mHref = href.match(/[?&]p=(\d+)/);
    if (mHref) rawId = mHref[1];
  }

  return rawId ? String(rawId).trim() : '';
}

function pickImageUrl($el) {
  const img = $el.find('img').first();
  if (!img.length) return '';
  const candidates = [
    img.attr('data-src'),
    img.attr('data-lazy-src'),
    img.attr('data-original'),
    img.attr('src'),
  ];
  for (const c of candidates) {
    if (c && !c.startsWith('data:image')) {
      return resolveAbsoluteUrl(c.trim());
    }
  }
  return '';
}

function parseVideoItem($, el) {
  const $el = $(el);
  const linkEl = $el.find('a').first();
  const href = linkEl.attr('href') || '';
  const rawId = extractRawId($el, href);
  if (!rawId) return null;

  const title = (
    linkEl.attr('title') ||
    $el.find('.entry-header span').first().text() ||
    $el.find('.entry-header .title').first().text() ||
    $el.find('.entry-header').first().text() ||
    $el.find('img').attr('alt') ||
    `Video ${rawId}`
  ).trim();

  const poster = pickImageUrl($el);
  const duration = $el.find('.duration').first().text().trim();
  const views = $el.find('.views').first().text().trim();
  const hd = $el.find('.hd-video').first().text().trim();
  const ribbon = duration || (views ? `${views} views` : hd);

  const item = {
    id: `phe69:${rawId}`,
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

  $('article.thumb-block, article.loop-video, article.video-preview-item').each((_, el) => {
    const item = parseVideoItem($, el);
    if (item && !seen.has(item.rawId)) {
      seen.add(item.rawId);
      videos.push(item);
    }
  });

  return videos;
}

async function getLatest(page = 1, category = '') {
  const catSlug = CATEGORY_MAP[category] || category;
  let reqPath = '/';

  if (catSlug && catSlug !== 'all' && catSlug !== 'tat-ca') {
    const cleanSlug = String(catSlug).replace(/^\/+|\/+$/g, '');
    reqPath = page === 1 ? `/${cleanSlug}/` : `/${cleanSlug}/page/${page}/`;
  } else {
    reqPath = page === 1 ? '/' : `/page/${page}/`;
  }

  try {
    const res = await client.get(reqPath);
    const $ = cheerio.load(res.data);
    return parseListingPage($, page);
  } catch (err) {
    if (err.response && err.response.status === 404) {
      return [];
    }
    console.error(`Phe69 getLatest error (page: ${page}, category: ${category}):`, err.message);
    return [];
  }
}

async function search(query, page = 1) {
  if (!query || !query.trim()) return [];

  const encoded = encodeURIComponent(query.trim());
  const reqPath = page === 1 ? `/?s=${encoded}` : `/page/${page}/?s=${encoded}`;

  try {
    const res = await client.get(reqPath);
    const $ = cheerio.load(res.data);
    return parseListingPage($, page);
  } catch (err) {
    if (err.response && err.response.status === 404) {
      return [];
    }
    console.error(`Phe69 search error for "${query}" (page ${page}):`, err.message);
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
    const targetUrl = info && info.href ? info.href : `/?p=${encodeURIComponent(rawId)}`;

    const res = await client.get(targetUrl, { maxRedirects: 5 });
    const $ = cheerio.load(res.data);
    const finalHref = (res.request && res.request.res && res.request.res.responseUrl) || resolveAbsoluteUrl(targetUrl);

    const title = (
      $('h1.entry-title').first().text().trim() ||
      $('h1').first().text().trim() ||
      $('meta[property="og:title"]').attr('content') ||
      (info ? info.title : `Video ${rawId}`)
    ).trim();

    const description = (
      $('meta[property="og:description"]').attr('content') ||
      $('meta[name="description"]').attr('content') ||
      $('.entry-content p').first().text().trim() ||
      ''
    ).trim();

    const rawPoster =
      (info && info.poster) ||
      $('meta[property="og:image"]').attr('content') ||
      $('.post-thumbnail img').first().attr('src') ||
      '';
    const poster = resolveAbsoluteUrl(rawPoster);

    const genres = [];
    $('.tags-list a, .video-tags a, .post-tags a, a[rel="tag"]').each((_, el) => {
      const g = $(el).text().trim();
      if (g && !genres.includes(g)) genres.push(g);
    });

    const iframeEl = $(
      '.responsive-player iframe, .video-player iframe, iframe[src*="play."], iframe'
    ).first();
    let iframeSrc = iframeEl.attr('src') || iframeEl.attr('data-src') || '';
    if (iframeSrc.startsWith('//')) {
      iframeSrc = 'https:' + iframeSrc;
    } else if (iframeSrc) {
      iframeSrc = resolveAbsoluteUrl(iframeSrc);
    }

    const details = {
      id: `phe69:${rawId}`,
      rawId: String(rawId),
      name: title,
      poster,
      background: poster,
      description,
      genres,
      href: finalHref,
      iframeSrc,
      type: 'movie',
    };

    if (videoDetailsCache.size >= 500 && !videoDetailsCache.has(String(rawId))) {
      videoDetailsCache.delete(videoDetailsCache.keys().next().value);
    }
    videoDetailsCache.set(String(rawId), { data: details, time: Date.now() });
    return details;
  } catch (err) {
    console.error(`Phe69 getVideoDetails error for ${rawId}:`, err.message);
    const info = videoInfoCache.get(String(rawId));
    return {
      id: `phe69:${rawId}`,
      rawId: String(rawId),
      name: info ? info.title : `Video ${rawId}`,
      poster: info ? info.poster : '',
      background: info ? info.poster : '',
      description: '',
      genres: [],
      href: info ? info.href : '',
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
        'Referer': details.href || (getBaseUrl() + '/'),
        'User-Agent': USER_AGENT,
      },
      timeout: 12000,
    });

    const html = typeof iframeRes.data === 'string' ? iframeRes.data : '';
    const match =
      html.match(/const\s+hlsSource\s*=\s*["']([^"']+)["']/i) ||
      html.match(/hlsSource\s*=\s*["']([^"']+)["']/i) ||
      html.match(/hls\.loadSource\(\s*["']([^"']+)["']\s*\)/i) ||
      html.match(/["']file["']\s*:\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/i) ||
      html.match(/file\s*:\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/i) ||
      html.match(/<source[^>]+src=["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/i) ||
      html.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)["']/i);

    if (match && match[1]) {
      const iframeOrigin = new URL(iframeUrl).origin;
      const streamUrl = new URL(match[1], iframeUrl).toString();
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
    console.error(`Phe69 getRawManifestUrl error (id: ${rawId}):`, err.message);
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
      id: `phe69:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || '',
      ribbon: '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `phe69:${rawId}`,
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
