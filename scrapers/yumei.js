const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

function getBaseUrl() {
  return config.getConfig().yumeiBaseUrl || 'https://yumei-anime.com';
}

function getHostUrl() {
  return process.env.BASE_HOST || 'https://stremio.laboon.vn';
}

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const cache = new Map();
const TTL = 30 * 60 * 1000; // 30 mins

// Card metadata registry for SVG generation
const cardRegistry = new Map();

function encodePathId(type, path) {
  const clean = path.startsWith('/') ? path.slice(1) : path;
  return `yumei:${type}:${clean.replace(/\//g, '__')}`;
}

function decodePathId(id) {
  // Strip trailing :season:episode if attached by Stremio
  let cleanId = id.replace(/:\d+(?::\d+)?$/, '');
  if (cleanId.includes('__')) {
    const parts = cleanId.split(':');
    const pathPart = parts.find((p) => p.includes('__')) || parts.slice(2).join(':') || parts[parts.length - 1];
    return '/' + pathPart.replace(/__/g, '/');
  }
  let clean = cleanId.replace(/^yumei:(?:series|movie|path|ep|s|m):/, '');
  if (!clean.startsWith('/')) clean = '/' + clean;
  return clean;
}

function extractAllDataFromHtml(html) {
  const regex = /self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)(?:;|\n|<\/script>)/g;
  let match;
  let fullRsc = '';
  while ((match = regex.exec(html)) !== null) {
    let unescaped = match[1]
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\')
      .replace(/\\n/g, '\n')
      .replace(/\\r/g, '\r')
      .replace(/\\t/g, '\t');
    fullRsc += unescaped;
  }
  return fullRsc;
}

function extractJsonArray(text, key) {
  const searchStr = `"${key}":`;
  const startIdx = text.indexOf(searchStr);
  if (startIdx === -1) return [];

  const arrayStart = text.indexOf('[', startIdx + searchStr.length);
  if (arrayStart === -1) return [];

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = arrayStart; i < text.length; i++) {
    const char = text[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (char === '\\') {
      escape = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (!inString) {
      if (char === '[') depth++;
      else if (char === ']') {
        depth--;
        if (depth === 0) {
          const jsonStr = text.slice(arrayStart, i + 1)
            .replace(/"\$undefined"/g, 'null')
            .replace(/\$undefined/g, 'null');
          try {
            return JSON.parse(jsonStr);
          } catch (e) {
            return [];
          }
        }
      }
    }
  }
  return [];
}

async function fetchPage(path) {
  const cacheKey = `page:${path}`;
  if (cache.has(cacheKey)) {
    const item = cache.get(cacheKey);
    if (Date.now() - item.time < TTL) return item.data;
  }

  try {
    const baseUrl = getBaseUrl();
    const res = await axios.get(`${baseUrl}${path}`, {
      headers: {
        'User-Agent': USER_AGENT,
      },
      timeout: 12000,
    });
    const html = String(res.data);
    const rsc = extractAllDataFromHtml(html);
    const data = { html, rsc };
    cache.set(cacheKey, { data, time: Date.now() });
    return data;
  } catch (err) {
    console.error(`Error fetching page ${path}:`, err.message);
    return { html: '', rsc: '' };
  }
}

async function getFolderCards(path) {
  const { html } = await fetchPage(path);
  if (!html) return [];
  const $ = cheerio.load(html);
  const cards = [];

  $('a').each((i, el) => {
    const href = $(el).attr('href');
    const h2 = $(el).find('h2');
    if (href && href.startsWith('/thu-vien') && h2.length > 0) {
      const title = h2.text().trim();
      const count = $(el).find('span').first().text().replace(/<!--\s*-->/g, ' ').trim();
      const desc = $(el).find('p').text().trim();
      const poster = $(el).find('img').attr('src');
      cards.push({ title, count, desc, path: href, poster });
    }
  });
  return cards;
}

async function fetchEpisodesForPath(path, defaultPoster) {
  const { rsc } = await fetchPage(path);
  let list = extractJsonArray(rsc, 'episodes');

  if (list.length === 0) {
    let posts = extractJsonArray(rsc, 'posts');
    if (posts.length > 0 && (posts[0].watchPath || posts[0].path)) {
      const firstEpPath = posts[0].watchPath || posts[0].path;
      try {
        const epPage = await fetchPage(firstEpPath);
        const fullEps = extractJsonArray(epPage.rsc, 'episodes');
        if (fullEps.length > posts.length) {
          list = fullEps;
        } else {
          list = posts;
        }
      } catch (e) {
        list = posts;
      }
    } else {
      list = posts;
    }
  }

  const eps = list.map((p, idx) => {
    let epNum = idx + 1;
    const numMatch = p.title?.match(/(?:Tập|Ep|Episode|Tập phim|Bộc phát|Bộc Phát|Don)\s*(\d+)/i) || p.slug?.match(/(\d+)/);
    if (numMatch) {
      epNum = parseInt(numMatch[1], 10);
    }
    const thumbnail = p.imageUrls?.original || p.imageUrls?.medium || p.imageUrls?.thumbnail || p.imageUrls?.small || defaultPoster;
    const rawEpPath = p.watchPath || p.path;
    const epName = p.title || `Tập ${epNum}`;
    return {
      id: encodePathId('ep', rawEpPath),
      name: epName,
      episode: epNum,
      thumbnail,
      overview: epName,
      description: epName,
    };
  });

  // Sort episodes by natural episode number ascending (1, 2, 3...)
  eps.sort((a, b) => a.episode - b.episode);
  return eps;
}

// -------------------------------------------------------------
// DYNAMIC CATALOG BUILDERS (With SVG Card Metadata Registration)
// -------------------------------------------------------------

function registerItemMetadata(item) {
  cardRegistry.set(item.id, {
    badge: item.badge,
    title: item.cardTitle || item.name,
    subtitle: item.subtitle || item.description,
    category: item.categoryName || item.genre,
    bgUrl: item.rawPoster || item.poster,
  });
}

function applyCardUrls(it) {
  const host = getHostUrl();
  registerItemMetadata(it);
  it.poster = `${host}/thumb/yumei/${it.id}.svg?v=2`;
  it.background = `${host}/thumb/yumei/${it.id}.svg?v=2`;
  it.posterShape = 'poster';
}

// 1. TOP 4 WORLD CATEGORIES (Like /thu-vien home)
function getTopCategoriesItems() {
  const items = [
    {
      id: encodePathId('s', '/thu-vien/pokemon'),
      name: 'Pokemon (5 mục)',
      cardTitle: 'Pokemon',
      badge: '5 mục',
      subtitle: 'TV series, movie, specials và các tập Pokemon theo mùa.',
      categoryName: 'Pokemon',
      genre: 'Pokemon',
      type: 'series',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a3c9c912402ca0d30124e01/variants/medium.webp',
      description: 'Thế giới Pokemon: TV Series 29 mùa, Horizons 8 chương, Phim điện ảnh, Specials và Pikachu Shorts.',
      genres: ['Pokemon', 'Yumei Anime'],
    },
    {
      id: encodePathId('s', '/thu-vien/super-sentai'),
      name: 'Super Sentai (18 mục)',
      cardTitle: 'Super Sentai',
      badge: '18 mục',
      subtitle: 'Những đội Sentai và live-action được gom thành từng series.',
      categoryName: 'Super Sentai',
      genre: 'Super Sentai',
      type: 'series',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a1ee411dadf8f2c621e57d4/variants/medium.webp',
      description: 'Tổng hợp 18 series Siêu Nhân Super Sentai từ Gaoranger, Hurricaneger, Dekaranger đến King-Ohger, Boonboomger.',
      genres: ['Super Sentai', 'Tokusatsu'],
    },
    {
      id: encodePathId('s', '/thu-vien/anime-khac'),
      name: 'Anime khác (6 mục)',
      cardTitle: 'Anime khác',
      badge: '6 mục',
      subtitle: 'Các bộ anime ngoài Pokemon, được tách thành từng nhánh riêng.',
      categoryName: 'Anime khác',
      genre: 'Anime khác',
      type: 'series',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a5a3d61342fb9db12a1796f/variants/medium.webp',
      description: 'Các bộ Anime Vietsub tuổi thơ: Thủ Lĩnh Thẻ Bài Sakura, Hiệp Sĩ Lợn Buurin, 12 Con Giáp, Chiến Long Xạ Thủ, Áo Giáp Vàng, Ghibli.',
      genres: ['Anime khác', 'Anime Vietsub'],
    },
    {
      id: encodePathId('s', '/thu-vien/power-rangers'),
      name: 'Power Rangers (2 mục)',
      cardTitle: 'Power Rangers',
      badge: '2 mục',
      subtitle: 'Huyền thoại 5 Anh Em Siêu Nhân Power Rangers kinh điển.',
      categoryName: 'Power Rangers',
      genre: 'Power Rangers',
      type: 'series',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a1ee410dadf8f2c621e57d0/variants/medium.webp',
      description: 'Mighty Morphin Power Rangers Season 1 (60 tập), Season 2 (32 tập) và các phim điện ảnh.',
      genres: ['Power Rangers', 'Tokusatsu'],
    },
  ];

  items.forEach(applyCardUrls);
  return items;
}

// 2. POKEMON ITEMS (5 Main Branch Cards matching https://yumei-anime.com/thu-vien/pokemon)
async function getPokemonCatalogItems() {
  const mainCards = [
    {
      id: encodePathId('s', '/thu-vien/pokemon/tv-series'),
      name: 'Pokemon: TV Series (29 mục)',
      cardTitle: 'TV Series',
      badge: '29 mục',
      subtitle: 'Hành trình 29 mùa của Satoshi & Pikachu',
      categoryName: 'Pokemon TV Series',
      type: 'series',
      genre: 'Pokemon',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a16c0c4edca254fdde172f5/variants/medium.webp',
      description: 'Pokemon TV Series: Trọn bộ 29 mùa với hơn 1.200 tập phim của Satoshi và Pikachu.',
      genres: ['Pokemon', 'Pokemon TV Series'],
    },
    {
      id: encodePathId('s', '/thu-vien/pokemon/horizons'),
      name: 'Pokemon: Horizons (8 mục)',
      cardTitle: 'Horizons',
      badge: '8 mục',
      subtitle: 'Thế hệ mới Liko & Roy với 8 chương',
      categoryName: 'Pokemon Horizons',
      type: 'series',
      genre: 'Pokemon',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a1ee40fdadf8f2c621e57cd/variants/medium.webp',
      description: 'Pokemon Horizons: Hành trình thế hệ mới của Liko & Roy qua 8 chương (148 tập phim).',
      genres: ['Pokemon', 'Pokemon Horizons'],
    },
    {
      id: encodePathId('s', '/thu-vien/pokemon/movies'),
      name: 'Pokemon: The Movies (25 mục)',
      cardTitle: 'Movies',
      badge: '25 mục',
      subtitle: '25 Phim điện ảnh Pokemon chiếu rạp',
      categoryName: 'Pokemon Movies',
      type: 'series',
      genre: 'Pokemon',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a16c0e8edca254fdde17519/M23_poster_4.png',
      description: 'Tuyển tập 25 phim điện ảnh Pokemon chiếu rạp từ 1998 đến nay.',
      genres: ['Pokemon', 'Phim Chiếu Rạp'],
    },
    {
      id: encodePathId('s', '/thu-vien/pokemon/tv-specials'),
      name: 'Pokemon: TV Specials (56 mục)',
      cardTitle: 'TV Specials',
      badge: '56 mục',
      subtitle: 'Tổng hợp các tập phim đặc biệt ngoại truyện',
      categoryName: 'Pokemon Specials',
      type: 'series',
      genre: 'Pokemon',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a16c0b2edca254fdde171d5/variants/medium.webp',
      description: 'Tổng hợp 56 tập phim đặc biệt Pokemon TV Specials Vietsub.',
      genres: ['Pokemon', 'Pokemon Specials'],
    },
    {
      id: encodePathId('s', '/thu-vien/pokemon/pikachu-shorts'),
      name: 'Pokemon: Pikachu Shorts (26 mục)',
      cardTitle: 'Pikachu Shorts',
      badge: '26 mục',
      subtitle: 'Tuyển tập phim hoạt hình ngắn Pikachu',
      categoryName: 'Pikachu Shorts',
      type: 'series',
      genre: 'Pokemon',
      rawPoster: 'https://cdn.yumei-anime.com/assets/content/images/6a16c190dd62087d7e6678bb/PK26.png',
      description: 'Tuyển tập 26 tập phim hoạt hình ngắn hài hước của Pikachu.',
      genres: ['Pokemon', 'Pikachu Shorts'],
    },
  ];

  mainCards.forEach(applyCardUrls);
  return mainCards;
}

// 3. SUPER SENTAI ITEMS
async function getSentaiCatalogItems() {
  const list = [];
  try {
    const cards = await getFolderCards('/thu-vien/super-sentai');
    for (const c of cards) {
      if (c.count && c.count.startsWith('0')) continue;
      if (c.path && c.path.includes('crossovers')) continue;
      const it = {
        id: encodePathId('s', c.path),
        name: `${c.title} (${c.count})`,
        cardTitle: c.title,
        badge: c.count || 'Sentai',
        subtitle: c.desc || 'Series Siêu Nhân Super Sentai',
        categoryName: 'Super Sentai',
        type: 'series',
        genre: 'Super Sentai',
        rawPoster: c.poster || 'https://cdn.yumei-anime.com/assets/content/images/6a1ee411dadf8f2c621e57d4/variants/medium.webp',
        description: c.desc || `${c.title} (${c.count}). Series Siêu Nhân Super Sentai Vietsub Full HD.`,
        genres: ['Super Sentai', 'Tokusatsu'],
      };
      applyCardUrls(it);
      list.push(it);
    }
  } catch (e) {}
  return list;
}

// 4. POWER RANGERS ITEMS
async function getPowerRangersCatalogItems() {
  const list = [];
  try {
    const cards = await getFolderCards('/thu-vien/power-rangers');
    for (const c of cards) {
      const it = {
        id: encodePathId('s', c.path),
        name: `${c.title} (${c.count})`,
        cardTitle: c.title,
        badge: c.count || 'Power Rangers',
        subtitle: c.desc || '5 Anh Em Siêu Nhân Power Rangers',
        categoryName: 'Power Rangers',
        type: 'series',
        genre: 'Power Rangers',
        rawPoster: c.poster || 'https://cdn.yumei-anime.com/assets/content/images/6a1ee410dadf8f2c621e57d0/variants/medium.webp',
        description: c.desc || `${c.title} (${c.count}). 5 Anh Em Siêu Nhân Power Rangers Vietsub Full HD.`,
        genres: ['Power Rangers', 'Tokusatsu'],
      };
      applyCardUrls(it);
      list.push(it);
    }
  } catch (e) {}
  return list;
}

// 5. ANIME KHÁC ITEMS
async function getAnimeCatalogItems() {
  const list = [];
  try {
    const cards = await getFolderCards('/thu-vien/anime-khac');
    for (const c of cards) {
      const it = {
        id: encodePathId('s', c.path),
        name: `${c.title} (${c.count})`,
        cardTitle: c.title,
        badge: c.count || 'Anime',
        subtitle: c.desc || 'Anime Vietsub Tuổi Thơ',
        categoryName: 'Anime khác',
        type: 'series',
        genre: 'Anime khác',
        rawPoster: c.poster || 'https://cdn.yumei-anime.com/assets/content/images/6a5a3d61342fb9db12a1796f/variants/medium.webp',
        description: c.desc || `${c.title} (${c.count}). Phim hoạt hình Anime Vietsub Full HD.`,
        genres: ['Anime khác', 'Anime Vietsub'],
      };
      applyCardUrls(it);
      list.push(it);
    }
  } catch (e) {}
  return list;
}

// 6. MOVIES CATALOGS (Pokemon, Super Sentai, Power Rangers, Ghibli)
let cachedMovies = null;
let lastMoviesCache = 0;

async function fetchAllMovies() {
  if (cachedMovies && Date.now() - lastMoviesCache < TTL) {
    return cachedMovies;
  }

  const movies = [];

  // 1. Pokemon The Movies (25 movies)
  try {
    const { rsc } = await fetchPage('/thu-vien/pokemon/movies');
    const posts = extractJsonArray(rsc, 'posts');
    posts.forEach((p, idx) => {
      const rawPoster = p.imageUrls?.original || p.imageUrls?.medium || p.imageUrls?.thumbnail || 'https://cdn.yumei-anime.com/assets/content/images/6a16c0e8edca254fdde17519/M23_poster_4.png';
      const rawPath = p.path || p.watchPath;
      const it = {
        id: encodePathId('m', rawPath),
        name: p.title,
        cardTitle: p.title,
        badge: `Movie #${idx + 1}`,
        subtitle: 'Phim điện ảnh Pokemon chiếu rạp',
        categoryName: 'Pokemon The Movies',
        type: 'movie',
        genre: 'Pokemon The Movies',
        rawPoster,
        description: `Phim điện ảnh Pokemon: ${p.title}. Bản Vietsub Full HD từ Yumei Anime.`,
        genres: ['Pokemon The Movies', 'Phim Chiếu Rạp', 'Anime Vietsub'],
      };
      applyCardUrls(it);
      movies.push(it);
    });
  } catch (e) {
    console.error('Error scraping Pokemon movies:', e.message);
  }

  // 2. Super Sentai The Movies & Specials (Scrape across all 16 Sentai subfolders)
  try {
    const sentaiCards = await getFolderCards('/thu-vien/super-sentai');
    for (const sc of sentaiCards) {
      // Check deeper cards (e.g. subfolders like Movie, Specials, VS Crossover)
      const subCards = await getFolderCards(sc.path);
      for (const sub of subCards) {
        const isMovieSub = /movie|điện ảnh|chiếu rạp|special|đặc biệt|vs|crossover|v-cinema/i.test(sub.title);
        if (isMovieSub) {
          const { rsc } = await fetchPage(sub.path);
          const posts = extractJsonArray(rsc, 'posts');
          posts.forEach((p) => {
            const rawPoster = p.imageUrls?.original || p.imageUrls?.medium || p.imageUrls?.thumbnail || sub.poster || sc.poster;
            const rawPath = p.path || p.watchPath;
            const it = {
              id: encodePathId('m', rawPath),
              name: `[${sc.title}] ${p.title}`,
              cardTitle: p.title,
              badge: 'Sentai Movie',
              subtitle: `${sc.title} - Phim điện ảnh / Special`,
              categoryName: 'Super Sentai The Movies',
              type: 'movie',
              genre: 'Super Sentai The Movies',
              rawPoster,
              description: `Phim điện ảnh / Special Siêu Nhân: ${p.title} (${sc.title}). Bản Vietsub Full HD.`,
              genres: ['Super Sentai The Movies', 'Tokusatsu', 'Phim Chiếu Rạp'],
            };
            applyCardUrls(it);
            movies.push(it);
          });
        }
      }

      // Also check if direct posts inside the series folder are movies/specials
      const { rsc } = await fetchPage(sc.path);
      const directPosts = extractJsonArray(rsc, 'posts');
      directPosts.forEach((p) => {
        const isMovieTitle = /movie|the movie|điện ảnh|chiếu rạp|special|tập đặc biệt| vs |v-cinema|10 years|20 years/i.test(p.title);
        if (isMovieTitle) {
          const rawPoster = p.imageUrls?.original || p.imageUrls?.medium || p.imageUrls?.thumbnail || sc.poster;
          const rawPath = p.path || p.watchPath;
          const it = {
            id: encodePathId('m', rawPath),
            name: `[${sc.title}] ${p.title}`,
            cardTitle: p.title,
            badge: 'Sentai Movie',
            subtitle: `${sc.title} - Phim điện ảnh / Special`,
            categoryName: 'Super Sentai The Movies',
            type: 'movie',
            genre: 'Super Sentai The Movies',
            rawPoster,
            description: `Phim điện ảnh / Special Siêu Nhân: ${p.title} (${sc.title}). Bản Vietsub Full HD.`,
            genres: ['Super Sentai The Movies', 'Tokusatsu', 'Phim Chiếu Rạp'],
          };
          applyCardUrls(it);
          movies.push(it);
        }
      });
    }
  } catch (e) {
    console.error('Error scraping Super Sentai movies:', e.message);
  }

  // 3. Power Rangers The Movies
  try {
    const { rsc } = await fetchPage('/thu-vien/power-rangers/movie');
    const prPosts = extractJsonArray(rsc, 'posts');
    prPosts.forEach((p) => {
      const rawPoster = p.imageUrls?.original || p.imageUrls?.medium || p.imageUrls?.thumbnail || 'https://cdn.yumei-anime.com/assets/content/images/6a1ee410dadf8f2c621e57d2/variants/medium.webp';
      const rawPath = p.path || p.watchPath;
      const it = {
        id: encodePathId('m', rawPath),
        name: `Power Rangers: ${p.title}`,
        cardTitle: p.title,
        badge: 'PR Movie',
        subtitle: 'Phim điện ảnh Power Rangers',
        categoryName: 'Power Rangers The Movies',
        type: 'movie',
        genre: 'Power Rangers The Movies',
        rawPoster,
        description: `Phim điện ảnh Power Rangers: ${p.title}. Bản Vietsub Full HD.`,
        genres: ['Power Rangers The Movies', 'Tokusatsu', 'Phim Chiếu Rạp'],
      };
      applyCardUrls(it);
      movies.push(it);
    });
  } catch (e) {
    console.error('Error scraping Power Rangers movies:', e.message);
  }

  // Deduplicate movies by ID
  const uniqueMap = new Map();
  for (const m of movies) {
    if (!uniqueMap.has(m.id)) {
      uniqueMap.set(m.id, m);
    }
  }

  cachedMovies = Array.from(uniqueMap.values());
  lastMoviesCache = Date.now();
  return cachedMovies;
}

async function getMoviesCatalog(catalogId, extra = {}, requestedType = 'movie') {
  const allMovies = await fetchAllMovies();

  let filtered = allMovies;

  if (catalogId === 'yumei-pokemon-movies') {
    filtered = allMovies.filter((m) => (m.categoryName || '').includes('Pokemon') || (m.genre || '').includes('Pokemon'));
  } else if (catalogId === 'yumei-sentai-movies') {
    filtered = allMovies.filter((m) => (m.categoryName || '').includes('Sentai') || (m.genre || '').includes('Sentai'));
  } else if (catalogId === 'yumei-power-rangers-movies') {
    filtered = allMovies.filter((m) => (m.categoryName || '').includes('Power Rangers') || (m.genre || '').includes('Power Rangers'));
  } else if (catalogId === 'yumei-ghibli-movies') {
    filtered = allMovies.filter((m) => (m.categoryName || '').includes('Ghibli') || (m.genre || '').includes('Ghibli'));
  }

  const result = filterMovies(filtered, extra);
  const targetType = requestedType || 'movie';
  return result.map((m) => ({ ...m, type: targetType }));
}

function filterMovies(movies, extra) {
  if (!extra) return movies;
  let result = [...movies];
  if (extra.genre && extra.genre !== 'Tất cả') {
    const rawG = extra.genre.toLowerCase();
    if (rawG.includes('pokemon')) {
      result = result.filter((m) => (m.categoryName || '').includes('Pokemon') || (m.genre || '').includes('Pokemon'));
    } else if (rawG.includes('sentai') || rawG.includes('siêu nhân')) {
      result = result.filter((m) => (m.categoryName || '').includes('Sentai') || (m.genre || '').includes('Sentai'));
    } else if (rawG.includes('power rangers') || rawG.includes('tokusatsu')) {
      result = result.filter((m) => (m.categoryName || '').includes('Power Rangers') || (m.genre || '').includes('Power Rangers'));
    } else {
      const cleanG = rawG.replace(/[^\p{L}\p{N}\s]/gu, '').trim();
      result = result.filter(
        (m) =>
          (m.genre && m.genre.toLowerCase().includes(cleanG)) ||
          (m.categoryName && m.categoryName.toLowerCase().includes(cleanG)) ||
          (m.genres && m.genres.some((x) => x.toLowerCase().includes(cleanG)))
      );
    }
  }
  if (extra.search && typeof extra.search === 'string') {
    const q = extra.search.toLowerCase().trim();
    result = result.filter((m) => (m.name && m.name.toLowerCase().includes(q)) || (m.description && m.description.toLowerCase().includes(q)));
  }
  return result;
}

// 7. UNIFIED ALL-IN-ONE CATALOG HANDLER
async function getCatalog(catalogId, extra = {}, requestedType) {
  let items = [];

  if (catalogId === 'yumei-top' || catalogId === 'yumei-categories') {
    const g = extra?.genre || '';
    if (/pokemon/i.test(g)) {
      items = await getPokemonCatalogItems();
    } else if (/sentai|siêu nhân/i.test(g)) {
      items = await getSentaiCatalogItems();
    } else if (/power\s*rangers/i.test(g)) {
      items = await getPowerRangersCatalogItems();
    } else if (/anime/i.test(g) && !/thế giới/i.test(g)) {
      items = await getAnimeCatalogItems();
    } else {
      items = getTopCategoriesItems();
    }
  } else if (catalogId === 'yumei-pokemon') {
    const allPk = await getPokemonCatalogItems();
    if (extra?.genre && extra.genre !== 'Tất cả') {
      const g = extra.genre.toLowerCase();
      if (g.includes('tv series') || g.includes('mùa')) {
        items = allPk.filter((i) => i.name.includes('TV Series'));
      } else if (g.includes('horizons')) {
        items = allPk.filter((i) => i.name.includes('Horizons'));
      } else if (g.includes('movies') || g.includes('chiếu rạp')) {
        items = allPk.filter((i) => i.name.includes('The Movies'));
      } else if (g.includes('specials') || g.includes('đặc biệt')) {
        items = allPk.filter((i) => i.name.includes('Specials'));
      } else if (g.includes('shorts') || g.includes('pikachu')) {
        items = allPk.filter((i) => i.name.includes('Shorts'));
      } else {
        items = allPk;
      }
    } else {
      items = allPk;
    }
  } else if (catalogId === 'yumei-sentai' || catalogId === 'yumei-tokusatsu') {
    items = await getSentaiCatalogItems();
  } else if (catalogId === 'yumei-power-rangers') {
    items = await getPowerRangersCatalogItems();
  } else if (catalogId === 'yumei-anime' || catalogId === 'yumei-other-anime') {
    items = await getAnimeCatalogItems();
  } else if (
    catalogId === 'yumei-movies-all' ||
    catalogId === 'yumei-movies' ||
    catalogId === 'yumei-pokemon-movies' ||
    catalogId === 'yumei-sentai-movies' ||
    catalogId === 'yumei-power-rangers-movies' ||
    catalogId === 'yumei-ghibli-movies'
  ) {
    return await getMoviesCatalog(catalogId, extra, requestedType);
  } else if (catalogId === 'yumei-all' || catalogId === 'yumei-catalog') {
    const top4 = getTopCategoriesItems();
    const [pokemon, sentai, powerRangers, anime] = await Promise.all([
      getPokemonCatalogItems(),
      getSentaiCatalogItems(),
      getPowerRangersCatalogItems(),
      getAnimeCatalogItems(),
    ]);
    items = [...top4, ...pokemon, ...sentai, ...powerRangers, ...anime];
  }

  // Filter Search
  if (extra && typeof extra.search === 'string') {
    const q = extra.search.toLowerCase().trim();
    items = items.filter(
      (i) =>
        i.name.toLowerCase().includes(q) ||
        (i.genre && i.genre.toLowerCase().includes(q)) ||
        (i.description && i.description.toLowerCase().includes(q))
    );
  }

  // Ensure item.type matches requestedType so Stremio catalog parser never complains
  const targetType = requestedType || (items[0]?.id?.startsWith('yumei:m:') ? 'movie' : 'series');
  items = items.map((it) => ({
    ...it,
    type: targetType,
  }));

  return items;
}

// -------------------------------------------------------------
// METADATA RESOLUTION
// -------------------------------------------------------------

const seriesMetaCache = new Map();
const META_TTL = 60 * 60 * 1000; // 1 hour

async function getSeriesMeta(seriesId, requestedType = 'series') {
  const cacheKey = `${seriesId}:${requestedType}`;
  if (seriesMetaCache.has(cacheKey)) {
    const cached = seriesMetaCache.get(cacheKey);
    if (Date.now() - cached.time < META_TTL) {
      return cached.data;
    }
  }

  const webPath = decodePathId(seriesId);
  const fallbackPoster = 'https://cdn.yumei-anime.com/assets/content/images/6a16c0c4edca254fdde172f5/variants/medium.webp';

  if (!webPath) return null;

  const { html } = await fetchPage(webPath);
  let seriesTitle = '';
  const titleMatch = html.match(/<title>([^<|]+)/);
  if (titleMatch && titleMatch[1].trim()) {
    seriesTitle = titleMatch[1].trim();
  }
  if (!seriesTitle) {
    const pathParts = webPath.split('/');
    seriesTitle = pathParts[pathParts.length - 1].replace(/-/g, ' ').toUpperCase();
  }

  const subcards = await getFolderCards(webPath);
  const videos = [];
  const baseTime = Date.now();

  if (requestedType === 'movie') {
    const totalSub = subcards.length > 0 ? ` (${subcards.length} phần/mùa)` : '';
    const resultMeta = {
      id: seriesId,
      type: 'movie',
      name: seriesTitle,
      poster: fallbackPoster,
      background: fallbackPoster,
      posterShape: 'poster',
      description: `⚠️ Đây là Phim Bộ (Series)${totalSub}.\n👉 Để xem danh sách tất cả các mùa & tập phim (Tập 1, 2, 3...), vui lòng chuyển danh mục trên Stremio sang "Series" (Phim bộ).\n▶️ Bấm "Play" để xem ngay Tập 1.\n\n${seriesTitle} - Bản Vietsub Full HD từ Yumei Anime.`,
      genres: ['Anime Vietsub', 'Yumei Anime'],
    };

    seriesMetaCache.set(cacheKey, { data: resultMeta, time: Date.now() });
    return resultMeta;
  }

  // Requested as 'series'
  if (subcards.length > 0) {
    // Fetch seasons in parallel (max 10 at a time to prevent timeout)
    const BATCH_SIZE = 10;
    for (let i = 0; i < subcards.length; i += BATCH_SIZE) {
      const chunk = subcards.slice(i, i + BATCH_SIZE);
      const chunkResults = await Promise.all(
        chunk.map(async (sc, cIdx) => {
          const seasonNum = i + cIdx + 1;
          const eps = await fetchEpisodesForPath(sc.path, sc.poster || fallbackPoster);
          return eps.map((ep, eIdx) => {
            const releaseDate = new Date(Date.UTC(2020, 0, 1 + (eIdx % 365))).toISOString();
            return {
              id: `${seriesId}:${seasonNum}:${eIdx + 1}`,
              epPath: ep.id,
              name: `${sc.title}: ${ep.name}`,
              season: seasonNum,
              episode: eIdx + 1,
              number: eIdx + 1,
              thumbnail: ep.thumbnail,
              overview: ep.overview,
              description: ep.description,
              released: releaseDate,
            };
          });
        })
      );
      chunkResults.forEach((sVids) => videos.push(...sVids));
    }
  } else {
    // Single season / direct episodes
    const eps = await fetchEpisodesForPath(webPath, fallbackPoster);
    eps.forEach((ep, eIdx) => {
      const releaseDate = new Date(Date.UTC(2020, 0, 1 + (eIdx % 365))).toISOString();
      videos.push({
        id: `${seriesId}:1:${eIdx + 1}`,
        epPath: ep.id,
        name: ep.name,
        season: 1,
        episode: eIdx + 1,
        number: eIdx + 1,
        thumbnail: ep.thumbnail,
        overview: ep.overview,
        description: ep.description,
        released: releaseDate,
      });
    });
  }

  // Sort videos by season ascending, episode ascending (1, 2, 3...)
  videos.sort((a, b) => {
    if (a.season !== b.season) return a.season - b.season;
    return a.episode - b.episode;
  });

  const resultMeta = {
    id: seriesId,
    type: 'series',
    name: seriesTitle,
    poster: fallbackPoster,
    background: fallbackPoster,
    posterShape: 'poster',
    description: `${seriesTitle}. Trọn bộ Vietsub Full HD từ Yumei Anime.`,
    genres: ['Anime Vietsub', 'Yumei Anime'],
    videos,
  };

  seriesMetaCache.set(cacheKey, { data: resultMeta, time: Date.now() });
  return resultMeta;
}

async function getMovieMeta(movieId, requestedType = 'movie') {
  const webPath = decodePathId(movieId);

  let movies = cachedMovies;
  if (!movies) {
    try {
      movies = await fetchAllMovies();
    } catch (e) {}
  }

  let found = movies ? movies.find((m) => decodePathId(m.id) === webPath) : null;
  let title = found ? found.name : webPath.split('/').pop().replace(/-/g, ' ');
  let poster = (found && (found.rawPoster || found.poster)) || 'https://cdn.yumei-anime.com/assets/content/images/6a16c0e8edca254fdde17519/M23_poster_4.png';
  let desc = (found && found.description) || `${title}. Bản Vietsub Full HD từ Yumei Anime.`;
  let genres = (found && found.genres) || ['Phim Chiếu Rạp', 'Yumei Anime'];

  const meta = {
    id: movieId,
    type: requestedType || 'movie',
    name: title,
    poster,
    background: poster,
    posterShape: 'poster',
    description: desc,
    genres,
  };

  if (requestedType === 'series') {
    meta.videos = [
      {
        id: `${movieId}:1:1`,
        epPath: movieId,
        name: title,
        season: 1,
        episode: 1,
        number: 1,
        released: '2020-01-01T00:00:00.000Z',
      },
    ];
  }

  return meta;
}

async function getStreams(id) {
  let targetId = id;

  // 1. Support Stremio Android TV / Mobile format: "series_id:season:episode"
  const seasonEpMatch = id.match(/^(yumei:.+?):(\d+):(\d+)$/);
  if (seasonEpMatch) {
    const seriesId = seasonEpMatch[1];
    const seasonNum = parseInt(seasonEpMatch[2], 10);
    const epNum = parseInt(seasonEpMatch[3], 10);

    try {
      const meta = await getSeriesMeta(seriesId);
      if (meta && meta.videos) {
        const found = meta.videos.find((v) => v.season === seasonNum && (v.episode === epNum || v.number === epNum));
        if (found) {
          targetId = found.epPath || found.id;
        }
      }
    } catch (e) {
      console.error('Error resolving series episode for Android TV:', e.message);
    }
  }

  const webPath = decodePathId(targetId);
  const streams = [];

  if (!webPath) return [];

  try {
    const { rsc } = await fetchPage(webPath);
    const clean = rsc.replace(/"\$undefined"/g, 'null');

    // Extract HLS sources
    let srcMatches = [...clean.matchAll(/"hlsUrl":"([^"]+)"/g)].map((m) => m[1]);
    let iframeMatches = [...clean.matchAll(/"iframeUrl":"([^"]+)"/g)].map((m) => m[1]);

    // If no direct video sources on this page (e.g. folder/series page), fetch first episode from meta
    if (srcMatches.length === 0 && iframeMatches.length === 0) {
      const meta = await getSeriesMeta(targetId);
      if (meta && meta.videos && meta.videos.length > 0) {
        const firstEpPath = decodePathId(meta.videos[0].epPath || meta.videos[0].id);
        const firstPage = await fetchPage(firstEpPath);
        const cleanFirst = firstPage.rsc.replace(/"\$undefined"/g, 'null');
        srcMatches = [...cleanFirst.matchAll(/"hlsUrl":"([^"]+)"/g)].map((m) => m[1]);
        iframeMatches = [...cleanFirst.matchAll(/"iframeUrl":"([^"]+)"/g)].map((m) => m[1]);
      }
    }

    const uniqueHls = [...new Set(srcMatches)];
    uniqueHls.forEach((hlsUrl, idx) => {
      const isR2 = hlsUrl.includes('r2.yumei-anime.com');
      const serverName = isR2 ? 'Server #2 (Cloudflare R2 Direct)' : `Server #${idx + 1} (Cloudflare CDN)`;

      streams.push({
        name: 'Yumei Anime',
        title: `${serverName} - Full HD 1080p/720p`,
        url: hlsUrl,
        behaviorHints: {
          notWebReady: false,
          proxyHeaders: {
            request: {
              'User-Agent': USER_AGENT,
              'Referer': 'https://yumei-anime.com/',
            },
          },
        },
      });
    });

    // Extract iframeUrl if available
    const uniqueIframes = [...new Set(iframeMatches)];
    uniqueIframes.forEach((iUrl, idx) => {
      streams.push({
        name: 'Yumei Web Player',
        title: `Player Embed Web #${idx + 1}`,
        externalUrl: iUrl,
      });
    });
  } catch (err) {
    console.error(`Error fetching streams for ${id}:`, err.message);
  }

  return streams;
}

function clearCache() {
  cache.clear();
  seriesMetaCache.clear();
  cachedMovies = null;
  lastMoviesCache = 0;
}

function getCardRegistry() {
  return cardRegistry;
}

module.exports = {
  getCatalog,
  getMoviesCatalog,
  getSeriesMeta,
  getMovieMeta,
  getStreams,
  getBaseUrl,
  getHostUrl,
  clearCache,
  encodePathId,
  decodePathId,
  getCardRegistry,
  fetchPage,
  getFolderCards,
  extractJsonArray,
  extractAllDataFromHtml,
  USER_AGENT,
};
