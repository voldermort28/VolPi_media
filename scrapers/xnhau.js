const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().xnhauBaseUrl || 'https://xnhau.pink';
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
  'tat-ca': '',
  'viet-nam': 'vietnam',
  'vietnam': 'vietnam',
  'tu-quay': 'tu-quay',
  'gai-xinh': 'gai-xinh',
  'gai-teen': 'gai-teen',
  'thu-dam': 'thu-dam',
  'hoc-sinh': 'hoc-sinh',
  'vu-bu': 'vu-bu',
  'loan-luan': 'loan-luan',
  'sinh-vien': 'sinh-vien',
  'dit-bu': 'dit-bu-mong-to',
  'quay-len': 'quay-len',
  'cap-doi': 'cap-doi-nguoi-yeu',
  'may-bay': 'may-bay-mbbg',
};

const GENRE_TO_CAT = {
  'Tất cả': '',
  'Việt Nam': 'vietnam',
  'Tự quay': 'tu-quay',
  'Gái Xinh': 'gai-xinh',
  'Gái Teen': 'gai-teen',
  'Thủ dâm': 'thu-dam',
  'Học sinh': 'hoc-sinh',
  'Vú bự': 'vu-bu',
  'Loạn luân': 'loan-luan',
  'Sinh viên': 'sinh-vien',
  'Đít bự': 'dit-bu-mong-to',
  'Quay lén': 'quay-len',
  'Cặp đôi': 'cap-doi-nguoi-yeu',
  'Máy bay': 'may-bay-mbbg',
};

const videoInfoCache = new Map();
const manifestUrlCache = new Map();
const videoDetailsCache = new Map();

function removeAccents(str) {
  if (!str) return '';
  return str
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-');
}

function parseVideoItem($, el) {
  const $el = $(el);
  const linkEl = $el.find('a').first();
  const href = linkEl.attr('href') || '';

  let rawId = $el.attr('data-vid') || linkEl.attr('data-vid') || '';
  if (!rawId && href) {
    const m = href.match(/\/video\/(\d+)/);
    if (m) rawId = m[1];
  }

  if (!rawId) return null;

  const currentBase = getBaseUrl();
  const title = linkEl.attr('title') || $el.find('.title').text().trim() || $el.find('img').attr('alt') || `Video ${rawId}`;

  const imgEl = $el.find('img').first();
  let poster = imgEl.attr('data-original') || imgEl.attr('data-webp') || imgEl.attr('src') || '';
  if (poster && poster.startsWith('data:image')) {
    poster = imgEl.attr('data-original') || imgEl.attr('data-webp') || '';
  }
  if (poster && poster.startsWith('/')) {
    poster = `${currentBase}${poster}`;
  }

  const ribbon = $el.find('.is-hd').text().trim() || $el.find('.xnvn-dur').text().trim() || '';

  const item = {
    id: `xnhau:${rawId}`,
    rawId: String(rawId),
    title,
    poster,
    href: href.startsWith('http') ? href : `${currentBase}${href}`,
    ribbon,
  };

  if (videoInfoCache.size >= 1000 && !videoInfoCache.has(String(rawId))) {
    videoInfoCache.delete(videoInfoCache.keys().next().value);
  }
  videoInfoCache.set(String(rawId), item);
  return item;
}

async function getLatest(page = 1, category = '') {
  let catSlug = CATEGORY_MAP[category] || GENRE_TO_CAT[category] || category || '';
  catSlug = catSlug.trim();

  let path = '/';
  if (catSlug && catSlug !== 'all' && catSlug !== 'tat-ca') {
    path = page === 1 ? `/the-loai/${catSlug}/` : `/the-loai/${catSlug}/${page}/`;
  } else {
    path = page === 1 ? '/clip-sex-moi/' : `/clip-sex-moi/${page}/`;
  }

  try {
    const res = await client.get(path);
    const $ = cheerio.load(res.data);
    const videos = [];
    const seen = new Set();

    $('.list-videos .item').each((_, el) => {
      const item = parseVideoItem($, el);
      if (item && !seen.has(item.rawId)) {
        seen.add(item.rawId);
        videos.push(item);
      }
    });

    return videos;
  } catch (err) {
    console.error(`xNhau getLatest error (page: ${page}):`, err.message);
    return [];
  }
}

async function search(query, page = 1) {
  if (!query || !query.trim()) return [];

  const cleanQ = removeAccents(query.trim()).replace(/\s+/g, '-');
  const path = page === 1 ? `/search/${encodeURIComponent(cleanQ)}/` : `/search/${encodeURIComponent(cleanQ)}/${page}/`;

  try {
    const res = await client.get(path);
    const $ = cheerio.load(res.data);
    const videos = [];
    const seen = new Set();

    $('.list-videos .item').each((_, el) => {
      const item = parseVideoItem($, el);
      if (item && !seen.has(item.rawId)) {
        seen.add(item.rawId);
        videos.push(item);
      }
    });

    return videos;
  } catch (err) {
    console.error(`xNhau search error for "${query}":`, err.message);
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
    const targetUrl = info && info.href ? info.href : `/video/${rawId}/v/`;

    const res = await client.get(targetUrl, { maxRedirects: 5 });
    const html = res.data;
    const $ = cheerio.load(html);

    const title = $('h1').text().trim() ||
      $('meta[property="og:title"]').attr('content') ||
      (info ? info.title : `Video ${rawId}`);

    const description = $('meta[name="description"]').attr('content') || '';

    let poster = $('meta[property="og:image"]').attr('content') ||
      (info ? info.poster : '');

    const genres = [];
    $('.item-tags a, a[href*="/the-loai/"]').each((_, el) => {
      const g = $(el).text().trim();
      if (g && !genres.includes(g)) genres.push(g);
    });

    const vUrlMatch = html.match(/video_url:\s*['"]([^'"]+)['"]/);
    const vAltMatch = html.match(/video_alt_url:\s*['"]([^'"]+)['"]/);
    const vAlt2Match = html.match(/video_alt_url2:\s*['"]([^'"]+)['"]/);

    const streams = [];
    if (vAlt2Match && !vAlt2Match[1].includes('login') && vAlt2Match[1].startsWith('http')) {
      streams.push({ quality: '1080p', title: 'Server 1080p (FHD)', url: vAlt2Match[1] });
    }
    if (vAltMatch && !vAltMatch[1].includes('login') && vAltMatch[1].startsWith('http')) {
      streams.push({ quality: '720p', title: 'Server 720p (HD)', url: vAltMatch[1] });
    }
    if (vUrlMatch && !vUrlMatch[1].includes('login') && vUrlMatch[1].startsWith('http')) {
      streams.push({ quality: '480p', title: 'Server 480p (SD)', url: vUrlMatch[1] });
    }

    const details = {
      id: `xnhau:${rawId}`,
      rawId: String(rawId),
      name: title,
      poster,
      description,
      genres,
      streams,
    };

    if (videoDetailsCache.size >= 500 && !videoDetailsCache.has(String(rawId))) {
      videoDetailsCache.delete(videoDetailsCache.keys().next().value);
    }
    videoDetailsCache.set(String(rawId), { time: Date.now(), data: details });
    return details;
  } catch (err) {
    console.error(`xNhau getVideoDetails error (id: ${rawId}):`, err.message);
    const info = videoInfoCache.get(String(rawId));
    return {
      id: `xnhau:${rawId}`,
      rawId: String(rawId),
      name: info ? info.title : `Video ${rawId}`,
      poster: info ? info.poster : '',
      description: '',
      genres: [],
      streams: [],
    };
  }
}

async function getVideoStreamUrl(rawId, serverOrQuality = '1') {
  const cacheKey = `${rawId}_${serverOrQuality}`;
  const cached = manifestUrlCache.get(cacheKey);
  if (cached && Date.now() - cached.time < 1800000) {
    return cached.url;
  }

  try {
    const details = await getVideoDetails(rawId);
    if (!details || !details.streams || details.streams.length === 0) {
      return null;
    }

    let targetStream = null;
    if (serverOrQuality === '1' || serverOrQuality === 'master' || serverOrQuality === '720p' || serverOrQuality === '1080p') {
      targetStream = details.streams[0];
    } else if (serverOrQuality === '2' || serverOrQuality === 'backup' || serverOrQuality === '480p') {
      targetStream = details.streams.length > 1 ? details.streams[1] : details.streams[0];
    } else {
      targetStream = details.streams[0];
    }

    if (!targetStream || !targetStream.url) {
      return null;
    }

    let directUrl = targetStream.url;
    try {
      const headRes = await client.get(targetStream.url, {
        headers: { 'Referer': getBaseUrl() + '/' },
        maxRedirects: 0,
        validateStatus: status => status >= 200 && status < 400,
        timeout: 6000,
      });
      if (headRes.headers && headRes.headers.location) {
        directUrl = headRes.headers.location;
      }
    } catch (e) {}

    manifestUrlCache.set(cacheKey, { time: Date.now(), url: directUrl });
    return directUrl;
  } catch (err) {
    console.error(`xNhau getVideoStreamUrl error (id: ${rawId}):`, err.message);
    return null;
  }
}

async function getVideoInfo(rawId) {
  if (videoInfoCache.has(String(rawId))) {
    return videoInfoCache.get(String(rawId));
  }
  try {
    const details = await getVideoDetails(rawId);
    const info = {
      id: `xnhau:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || '',
      ribbon: '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `xnhau:${rawId}`,
      rawId: String(rawId),
      title: `Video ${rawId}`,
      poster: '',
      ribbon: '',
    };
  }
}

function clearCache() {
  resolvedBaseUrl = null;
  videoInfoCache.clear();
  manifestUrlCache.clear();
  videoDetailsCache.clear();
}

module.exports = {
  getLatest,
  search,
  getVideoDetails,
  getVideoInfo,
  getVideoStreamUrl,
  getBaseUrl,
  clearCache,
  USER_AGENT,
  CATEGORY_MAP,
  GENRE_TO_CAT,
};
