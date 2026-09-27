const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().vlxxBaseUrl || 'https://vlxx.phd';
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

const videoInfoCache = new Map();

function parseVideoItem($, el) {
  const $el = $(el);
  const rawId = $el.attr('id') || '';
  const matchId = rawId.match(/video-(\d+)/);
  const linkEl = $el.find('a').first();
  const href = linkEl.attr('href') || '';
  
  let id = matchId ? matchId[1] : null;
  if (!id && href) {
    const hrefMatch = href.match(/\/(\d+)\/?$/);
    if (hrefMatch) id = hrefMatch[1];
  }

  if (!id) return null;

  const currentBase = getBaseUrl();
  const title = linkEl.attr('title') || $el.find('.video-name a').text().trim() || $el.find('img').attr('alt') || `Video ${id}`;
  let poster = $el.find('img').attr('data-original') || $el.find('img').attr('src') || `${currentBase}/img/${id}.jpg`;
  if (poster && poster.startsWith('data:image')) {
    poster = `${currentBase}/img/${id}.jpg`;
  }
  if (poster && poster.startsWith('/')) {
    poster = `${currentBase}${poster}`;
  }

  const ribbon = $el.find('.ribbon').text().trim() || '';

  const item = {
    id: `vlxx:${id}`,
    rawId: id,
    title,
    poster,
    href,
    ribbon,
  };

  videoInfoCache.set(String(id), item);
  return item;
}

async function getLatest(page = 1) {
  const url = page === 1 ? '/' : `/new/${page}/`;
  const res = await client.get(url);
  const $ = cheerio.load(res.data);
  const videos = [];

  $('#video-list .video-item').each((_, el) => {
    const item = parseVideoItem($, el);
    if (item) videos.push(item);
  });

  return videos;
}

async function search(query, page = 1) {
  const slug = removeAccents(query);
  if (!slug) return [];

  const url = page === 1 ? `/search/${slug}/` : `/search/${slug}/${page}/`;
  try {
    const res = await client.get(url);
    const $ = cheerio.load(res.data);
    const videos = [];

    $('#video-list .video-item').each((_, el) => {
      const item = parseVideoItem($, el);
      if (item) videos.push(item);
    });

    return videos;
  } catch (err) {
    console.error(`Search error for "${query}":`, err.message);
    return [];
  }
}

async function getVideoDetails(rawId) {
  try {
    const res = await client.get(`/${rawId}`, {
      maxRedirects: 5,
    });
    const $ = cheerio.load(res.data);

    const title = $('h1.page-title').text().trim() || `Video ${rawId}`;
    const code = $('.video-code').text().trim() || undefined;
    const description = $('.video-description').text().trim() || '';
    const currentBase = getBaseUrl();
    const poster = `${currentBase}/img/${rawId}.jpg`;
    
    const genres = [];
    $('.category-tag a').each((_, el) => {
      genres.push($(el).text().trim());
    });

    const cast = [];
    $('.actress-tag a').each((_, el) => {
      cast.push($(el).text().trim());
    });

    return {
      id: `vlxx:${rawId}`,
      rawId,
      name: code ? `[${code}] ${title}` : title,
      poster,
      background: poster,
      description,
      genres,
      cast,
      code,
      type: 'movie',
    };
  } catch (err) {
    console.error(`Get video details error for ${rawId}:`, err.message);
    const currentBase = getBaseUrl();
    return {
      id: `vlxx:${rawId}`,
      rawId,
      name: `Video ${rawId}`,
      poster: `${currentBase}/img/${rawId}.jpg`,
      type: 'movie',
    };
  }
}

async function extractHlsFromEmbed(embedUrl) {
  try {
    const currentBase = getBaseUrl();
    let normalizedUrl = embedUrl;
    if (normalizedUrl.startsWith('//')) {
      normalizedUrl = 'https:' + normalizedUrl;
    } else if (normalizedUrl.startsWith('/')) {
      normalizedUrl = currentBase + normalizedUrl;
    }

    const res = await axios.get(normalizedUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Referer': currentBase + '/',
      },
      timeout: 8000,
      maxRedirects: 5,
    });

    const match = res.data.match(/window\.__SRC\s*=\s*(\[[\s\S]*?\]);/);
    if (!match) return null;

    const sources = JSON.parse(match[1]);
    if (Array.isArray(sources) && sources.length > 0 && sources[0].file) {
      return sources[0].file;
    }
  } catch (err) {
    console.error(`Extract embed error for ${embedUrl}:`, err.message);
  }
  return null;
}

const manifestUrlCache = new Map();

async function getRawManifestUrl(rawId, serverNum = 1) {
  const cacheKey = `${rawId}_${serverNum}`;
  const cached = manifestUrlCache.get(cacheKey);
  if (cached && Date.now() - cached.time < 3600000) {
    return cached.url;
  }

  // Ensure base domain is resolved before POSTing,
  // since HTTP 301/302 redirects transform POST to GET and lose form parameters
  if (!resolvedBaseUrl) {
    try {
      const probeRes = await client.get('/', { timeout: 5000 });
      if (probeRes.request && probeRes.request.res && probeRes.request.res.responseUrl) {
        updateResolvedBaseUrl(probeRes.request.res.responseUrl);
      }
    } catch (e) {
      // Continue with current base
    }
  }

  const currentBase = getBaseUrl();

  try {
    const res = await client.post(
      '/ajax.php',
      new URLSearchParams({
        vlxx_server: '1',
        id: String(rawId),
        server: String(serverNum),
      }).toString(),
      {
        baseURL: currentBase,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': `${currentBase}/${rawId}`,
        },
      }
    );

    if (res.data && res.data.player) {
      const $ = cheerio.load(res.data.player);
      let iframeSrc = $('iframe').attr('src');
      if (iframeSrc) {
        if (iframeSrc.startsWith('//')) {
          iframeSrc = 'https:' + iframeSrc;
        } else if (iframeSrc.startsWith('/')) {
          iframeSrc = currentBase + iframeSrc;
        }
        const hlsUrl = await extractHlsFromEmbed(iframeSrc);
        if (hlsUrl) {
          manifestUrlCache.set(cacheKey, { url: hlsUrl, time: Date.now() });
          return hlsUrl;
        }
      }
    }
  } catch (err) {
    console.error(`Error fetching manifest for server ${serverNum} (id: ${rawId}):`, err.message);
  }
  return null;
}

async function getVideoInfo(rawId) {
  if (videoInfoCache.has(String(rawId))) {
    return videoInfoCache.get(String(rawId));
  }
  const currentBase = getBaseUrl();
  try {
    const details = await getVideoDetails(rawId);
    const info = {
      id: `vlxx:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || `${currentBase}/img/${rawId}.jpg`,
      ribbon: details.code || '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `vlxx:${rawId}`,
      rawId: String(rawId),
      title: `Video ${rawId}`,
      poster: `${currentBase}/img/${rawId}.jpg`,
      ribbon: '',
    };
  }
}

function clearCache() {
  videoInfoCache.clear();
  manifestUrlCache.clear();
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
};
