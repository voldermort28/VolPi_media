const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/viet69');

const GENRE_TO_CAT = {
  'Tất cả': '',
  'Phim sex Việt mới': 'phim-sex-viet',
  'Sinh viên': 'sinh-vien',
  'Teen': 'teen',
  'Check hàng': 'check-hang',
  'Camera': 'camera',
  'BDSM': 'bdsm',
  'Máy bay bà già': 'may-bay-ba-gia',
  'Thủ dâm': 'thu-dam',
  'Video thành viên': 'bai-viet',
};

const manifest = {
  id: 'community.viet69',
  version: '1.0.0',
  name: 'Viet69 Stream',
  description: 'Xem video clip Viet69 trực tiếp trên Stremio không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['viet69:'],
  catalogs: [
    {
      type: 'movie',
      id: 'viet69-catalog',
      name: 'Viet69 Cập Nhật',
      extra: [
        {
          name: 'genre',
          options: [
            'Tất cả',
            'Phim sex Việt mới',
            'Sinh viên',
            'Teen',
            'Check hàng',
            'Camera',
            'BDSM',
            'Máy bay bà già',
            'Thủ dâm',
            'Video thành viên',
          ],
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
    if (type !== 'movie' || id !== 'viet69-catalog') {
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
      name: v.title,
      poster: v.poster || `${host}/thumb/viet69/${v.rawId}.jpg`,
      background: v.poster || `${host}/thumb/viet69/${v.rawId}.jpg`,
      posterShape: 'landscape',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('Viet69 catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('viet69:')) {
      return { meta: null };
    }

    const rawId = id.replace('viet69:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const poster = details.poster || `${host}/thumb/viet69/${rawId}.jpg`;

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
    console.error('Viet69 meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('viet69:')) {
      return { streams: [] };
    }

    const rawId = id.replace('viet69:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'Viet69',
        title: 'Server #2 (Full HD M3U8 - Không quảng cáo)',
        url: `${host}/viet69/hls/${rawId}/2/master.m3u8`,
      },
      {
        name: 'Viet69',
        title: 'Server #1 (Full HD - Không quảng cáo)',
        url: `${host}/viet69/hls/${rawId}/1/master.m3u8`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('Viet69 stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
