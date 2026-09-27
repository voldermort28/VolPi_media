const axios = require('axios');
const cheerio = require('cheerio');

const BASE_URL = 'https://vlxx.phd';
const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const client = axios.create({
  baseURL: BASE_URL,
  headers: {
    'User-Agent': USER_AGENT,
    'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
  },
  timeout: 10000,
});

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

  const title = linkEl.attr('title') || $el.find('.video-name a').text().trim() || $el.find('img').attr('alt') || `Video ${id}`;
  let poster = $el.find('img').attr('data-original') || $el.find('img').attr('src') || `${BASE_URL}/img/${id}.jpg`;
  if (poster && poster.startsWith('data:image')) {
    poster = `${BASE_URL}/img/${id}.jpg`;
  }
  if (poster && poster.startsWith('/')) {
    poster = `${BASE_URL}${poster}`;
  }

  const ribbon = $el.find('.ribbon').text().trim() || '';

  return {
    id: `vlxx:${id}`,
    rawId: id,
    title,
    poster,
    href,
    ribbon,
  };
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
    const poster = `${BASE_URL}/img/${rawId}.jpg`;
    
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
    return {
      id: `vlxx:${rawId}`,
      rawId,
      name: `Video ${rawId}`,
      poster: `${BASE_URL}/img/${rawId}.jpg`,
      type: 'movie',
    };
  }
}

async function extractHlsFromEmbed(embedUrl) {
  try {
    const res = await axios.get(embedUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Referer': BASE_URL,
      },
      timeout: 8000,
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

  try {
    const res = await client.post(
      '/ajax.php',
      new URLSearchParams({
        vlxx_server: '1',
        id: String(rawId),
        server: String(serverNum),
      }).toString(),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': `${BASE_URL}/${rawId}`,
        },
      }
    );

    if (res.data && res.data.player) {
      const $ = cheerio.load(res.data.player);
      const iframeSrc = $('iframe').attr('src');
      if (iframeSrc) {
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

module.exports = {
  getLatest,
  search,
  getVideoDetails,
  getRawManifestUrl,
  USER_AGENT,
};
