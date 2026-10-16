const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().viet69BaseUrl || 'https://viet69.be';
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
  'phim-sex-viet': 'sex-viet',
  'phim-moi': 'sex-viet',
  'sinh-vien': 'sinh-vien',
  'teen': 'teen',
  'check-hang': 'check-hang',
  'camera': 'camera',
  'bdsm': 'bdsm',
  'may-bay-ba-gia': 'may-bay-ba-gia',
  'thu-dam': 'thu-dam',
  'bai-viet': 'bai-viet',
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
    const postContainer = $el.closest('.post');
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

  let poster = $el.find('img').attr('src') ||
    $el.find('img').attr('data-src') ||
    $el.find('img').attr('data-original') ||
    '';

  const views = $el.find('.views .count').text().trim() || '';
  const likes = $el.find('.likes .count').text().trim() || '';
  const ribbon = views ? `${views} lượt xem` : (likes ? `${likes} thích` : '');

  const item = {
    id: `viet69:${rawId}`,
    rawId: String(rawId),
    title,
    poster,
    href,
    ribbon,
  };

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
    console.error(`Viet69 getLatest error (page: ${page}):`, err.message);
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
    console.error(`Viet69 search error for "${query}":`, err.message);
    return [];
  }
}

async function getVideoDetails(rawId) {
  const cached = videoDetailsCache.get(String(rawId));
  if (cached && Date.now() - cached.time < 1800000) {
    return cached.data;
  }

  try {
    // If we have cached href, use it; otherwise use WordPress ?p=rawId which redirects
    const info = videoInfoCache.get(String(rawId));
    const targetUrl = info && info.href ? info.href : `/?p=${rawId}`;

    const res = await client.get(targetUrl, {
      maxRedirects: 5,
    });
    const $ = cheerio.load(res.data);

    const title = $('h2.siteheading a').text().trim() ||
      $('h1.entry-title').text().trim() ||
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
    $('.entry-tags a, .tag-link').each((_, el) => {
      genres.push($(el).text().trim());
    });

    // Extract servers:
    const servers = [];
    $('.video2-btn').each((_, el) => {
      const btnText = $(el).text().trim() || `Server #${servers.length + 1}`;
      const dataVideo = $(el).attr('data-video');
      const dataType = $(el).attr('data-type') || '25';
      if (dataVideo) {
        try {
          const uuid = Buffer.from(dataVideo, 'base64').toString('ascii');
          servers.push({
            title: btnText,
            uuid,
            type: dataType,
          });
        } catch (e) {}
      }
    });

    if (servers.length === 0) {
      const dataMovie = $('.movieLoader').attr('data-movie');
      const dataType = $('.movieLoader').attr('data-type') || '25';
      if (dataMovie) {
        try {
          const uuid = Buffer.from(dataMovie, 'base64').toString('ascii');
          servers.push({
            title: 'Server #1 (Mặc định)',
            uuid,
            type: dataType,
          });
        } catch (e) {}
      }
    }

    const details = {
      id: `viet69:${rawId}`,
      rawId: String(rawId),
      name: title,
      poster,
      background: poster,
      description,
      genres,
      servers,
      type: 'movie',
    };

    videoDetailsCache.set(String(rawId), { data: details, time: Date.now() });
    return details;
  } catch (err) {
    console.error(`Viet69 getVideoDetails error for ${rawId}:`, err.message);
    const fallback = {
      id: `viet69:${rawId}`,
      rawId: String(rawId),
      name: `Video ${rawId}`,
      poster: '',
      genres: [],
      servers: [],
      type: 'movie',
    };
    return fallback;
  }
}

async function getRawManifestUrl(rawId, serverNum = 2) {
  const cacheKey = `${rawId}_${serverNum}`;
  const cached = manifestUrlCache.get(cacheKey);
  if (cached && Date.now() - cached.time < 3600000) {
    return cached.url;
  }

  try {
    const details = await getVideoDetails(rawId);
    if (!details || !details.servers || details.servers.length === 0) {
      return null;
    }

    // Determine target server:
    // If serverNum === 2, check Server #2 first. If serverNum === 1, check Server #1.
    const sIndex = Number(serverNum) - 1;
    let targetServer = details.servers[sIndex] || details.servers[0];

    // Priority: If Server #2 exists and serverNum wasn't strictly specified, Server #2 is the direct m3u8!
    if (!targetServer && details.servers.length > 0) {
      targetServer = details.servers[0];
    }

    if (!targetServer || !targetServer.uuid) {
      return null;
    }

    // Call emb.cd-vs.com API directly
    const apiUrl = `https://emb.cd-vs.com/api/get-video?id=${targetServer.uuid}`;
    const apiRes = await axios.get(apiUrl, {
      headers: {
        'Referer': `https://emb.cd-vs.com/embed/${targetServer.uuid}`,
        'User-Agent': USER_AGENT,
        'Accept': 'application/json, text/plain, */*',
      },
      timeout: 8000,
    });

    if (apiRes.data && apiRes.data.url) {
      const videoUrl = apiRes.data.url;
      manifestUrlCache.set(cacheKey, { url: videoUrl, time: Date.now() });
      return videoUrl;
    }

    // If server 1 was requested and returned non-playable link, try server 2 as fallback
    if (serverNum === 1 && details.servers.length > 1) {
      const s2 = details.servers[1];
      const fallbackRes = await axios.get(`https://emb.cd-vs.com/api/get-video?id=${s2.uuid}`, {
        headers: {
          'Referer': `https://emb.cd-vs.com/embed/${s2.uuid}`,
          'User-Agent': USER_AGENT,
        },
        timeout: 8000,
      });
      if (fallbackRes.data && fallbackRes.data.url) {
        manifestUrlCache.set(cacheKey, { url: fallbackRes.data.url, time: Date.now() });
        return fallbackRes.data.url;
      }
    }
  } catch (err) {
    console.error(`Viet69 getRawManifestUrl error for server ${serverNum} (id: ${rawId}):`, err.message);
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
      id: `viet69:${rawId}`,
      rawId: String(rawId),
      title: details.name || `Video ${rawId}`,
      poster: details.poster || '',
      ribbon: '',
    };
    videoInfoCache.set(String(rawId), info);
    return info;
  } catch (err) {
    return {
      id: `viet69:${rawId}`,
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
