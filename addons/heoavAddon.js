const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/heoav');

const GENRE_TO_CAT = {
  'Tất cả': 'phim-moi',
  'Hot Tuần': 'best-of-the-week',
  'Xem nhiều': 'xem-nhieu',
  'Thích nhiều': 'thich-nhieu',
  'Điểm cao': 'diem-cao',
  'Decen/LTX': 'decen-ltx',
  'Không che': 'uncensored',
  'Vietsub': 'vietsub',
  'Nữ sinh': 'nu-sinh',
  'Gái xinh': 'gai-xinh',
  'Loạn luân': 'loan-luan',
  'Vú to': 'vu-to',
  'Lén lút': 'len-lut',
  'Threesome': 'threesome',
  'Bố dượng': 'bo-duong',
  'Thuốc kích dục': 'thuoc-kich-duc',
};

const manifest = {
  id: 'community.heoav',
  version: '1.0.0',
  name: 'HeoAV Stream',
  description: 'Xem phim JAV Vietsub HD HeoAV trực tiếp không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['heoav:'],
  catalogs: [
    {
      type: 'movie',
      id: 'heoav-catalog',
      name: 'HeoAV Cập Nhật',
      extra: [
        {
          name: 'genre',
          options: Object.keys(GENRE_TO_CAT),
          isRequired: false,
        },
        { name: 'search', isRequired: false },
        { name: 'skip', isRequired: false },
      ],
    },
  ],
};

const builder = new addonBuilder(manifest);

builder.defineCatalogHandler(async (args) => {
  try {
    const { type, id, extra } = args;
    if (type !== 'movie' || id !== 'heoav-catalog') {
      return { metas: [] };
    }

    const skip = (extra && extra.skip) ? parseInt(extra.skip, 10) : 0;
    const page = Math.floor(skip / 30) + 1;

    let videos = [];
    if (extra && extra.search) {
      videos = await scraper.search(extra.search, page);
    } else {
      const selectedGenre = extra && extra.genre ? GENRE_TO_CAT[extra.genre] || 'phim-moi' : 'phim-moi';
      videos = await scraper.getLatest(page, selectedGenre);
    }

    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';
    const metas = videos.map((v) => ({
      id: v.id,
      rawId: v.rawId,
      name: v.title,
      poster: v.poster || `${host}/thumb/heoav/${v.rawId}.jpg`,
      background: v.poster || `${host}/thumb/heoav/${v.rawId}.jpg`,
      posterShape: 'landscape',
      ribbon: v.ribbon || '',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('HeoAV catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('heoav:')) {
      return { meta: null };
    }

    const rawId = id.replace('heoav:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const poster = details.poster || `${host}/thumb/heoav/${rawId}.jpg`;

    return {
      meta: {
        id: details.id,
        name: details.name,
        poster,
        background: poster,
        posterShape: 'landscape',
        description: details.description,
        genres: details.genres,
        type: 'movie',
      },
    };
  } catch (err) {
    console.error('HeoAV meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('heoav:')) {
      return { streams: [] };
    }

    const rawId = id.replace('heoav:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'HeoAV',
        title: 'Server #1 (Full HD M3U8 - Không quảng cáo)',
        url: `${host}/heoav/hls/${rawId}/master.m3u8`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('HeoAV stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
