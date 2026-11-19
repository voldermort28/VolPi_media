const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/phe69');

const GENRE_TO_CAT = {
  'Tất cả': '',
  'Việt Nam': 'sex-viet-nam',
  'Phim mới': 'phim-sex-moi',
  'Sinh viên': 'phim-sex-sinh-vien',
  'Không che': 'sex-khong-che',
  'Mình dây': 'sex-loli-minh-day',
  'Check hàng': 'check-hang',
  'Doggy': 'doggy',
  'Gái dâm': 'gai-dam',
  'Camera': 'camera',
  'BDSM': 'bdsm',
  'Máy bay': 'may-bay-ba-gia',
  'JAV HD': 'jav-hd',
};

const manifest = {
  id: 'community.phe69',
  version: '1.0.0',
  name: 'Phe69 Stream',
  description: 'Xem phim Phe69 Việt Nam & JAV Full HD trực tiếp không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['phe69:'],
  catalogs: [
    {
      type: 'movie',
      id: 'phe69-catalog',
      name: 'Phe69 Cập Nhật',
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
    if (type !== 'movie' || id !== 'phe69-catalog') {
      return { metas: [] };
    }

    const skip = (extra && extra.skip) ? parseInt(extra.skip, 10) : 0;
    const page = Math.floor(skip / 30) + 1;

    let videos = [];
    if (extra && extra.search) {
      videos = await scraper.search(extra.search, page);
    } else {
      const selectedGenre = extra && extra.genre ? GENRE_TO_CAT[extra.genre] || '' : '';
      videos = await scraper.getLatest(page, selectedGenre);
    }

    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';
    const metas = videos.map((v) => ({
      id: v.id,
      rawId: v.rawId,
      name: v.title,
      poster: v.poster || `${host}/thumb/phe69/${v.rawId}.jpg`,
      background: v.poster || `${host}/thumb/phe69/${v.rawId}.jpg`,
      posterShape: 'landscape',
      ribbon: v.ribbon || '',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('Phe69 catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('phe69:')) {
      return { meta: null };
    }

    const rawId = id.replace('phe69:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const poster = details.poster || `${host}/thumb/phe69/${rawId}.jpg`;

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
    console.error('Phe69 meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('phe69:')) {
      return { streams: [] };
    }

    const rawId = id.replace('phe69:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'Phe69',
        title: 'Server #1 (Full HD M3U8 - Không quảng cáo)',
        url: `${host}/phe69/hls/${rawId}/master.m3u8`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('Phe69 stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
