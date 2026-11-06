const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/xnhau');

const manifest = {
  id: 'community.xnhau',
  version: '1.0.0',
  name: 'xNhau Stream',
  description: 'Xem video clip xNhau trực tiếp trên Stremio không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['xnhau:'],
  catalogs: [
    {
      type: 'movie',
      id: 'xnhau-catalog',
      name: 'xNhau Cập Nhật',
      extra: [
        {
          name: 'genre',
          options: [
            'Tất cả',
            'Việt Nam',
            'Tự quay',
            'Gái Xinh',
            'Gái Teen',
            'Thủ dâm',
            'Học sinh',
            'Vú bự',
            'Loạn luân',
            'Sinh viên',
            'Đít bự',
            'Quay lén',
            'Cặp đôi',
            'Máy bay',
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
    if (type !== 'movie' || id !== 'xnhau-catalog') {
      return { metas: [] };
    }

    const skip = (extra && extra.skip) ? parseInt(extra.skip, 10) : 0;
    const page = Math.floor(skip / 28) + 1;

    let videos = [];
    if (extra && extra.search) {
      videos = await scraper.search(extra.search, page);
    } else {
      const selectedGenre = extra && extra.genre ? extra.genre : '';
      videos = await scraper.getLatest(page, selectedGenre);
    }

    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';
    const metas = videos.map((v) => ({
      id: v.id,
      name: v.title,
      poster: v.poster || `${host}/thumb/xnhau/${v.rawId}.jpg`,
      background: v.poster || `${host}/thumb/xnhau/${v.rawId}.jpg`,
      posterShape: 'landscape',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('xNhau catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('xnhau:')) {
      return { meta: null };
    }

    const rawId = id.replace('xnhau:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const poster = details.poster || `${host}/thumb/xnhau/${rawId}.jpg`;

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
    console.error('xNhau meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('xnhau:')) {
      return { streams: [] };
    }

    const rawId = id.replace('xnhau:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'xNhau',
        title: 'Server #1 (Full HD - Trực tiếp)',
        url: `${host}/xnhau/stream/${rawId}/1.mp4`,
      },
      {
        name: 'xNhau',
        title: 'Server #2 (Chuẩn SD - Dự phòng)',
        url: `${host}/xnhau/stream/${rawId}/2.mp4`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('xNhau stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
