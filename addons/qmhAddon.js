const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/qmh');

const GENRE_TO_CAT = {
  'Tất cả': '',
  'Việt Nam': 'phim-sex-viet-nam',
  'Clip sex': 'clip-sex',
  'Gái xinh': 'phim-sex-gai-xinh',
  'Học sinh': 'phim-sex-hoc-sinh',
  'Không che': 'phim-sex-khong-che',
  'Nhật Bản': 'phim-sex-nhat-ban',
  'Vietsub': 'phim-sex-vietsub',
  'Vụng trộm': 'phim-sex-vung-trom',
  'Loạn luân': 'phim-sex-loan-luan',
  'Châu Âu': 'phim-sex-chau-au',
  'Trung Quốc': 'phim-sex-trung-quoc',
  'Hàn Quốc': 'phim-sex-han-quoc',
  'VLXX': 'vlxx',
  'XNXX': 'xnxx',
  'XVIDEOS': 'xvideos',
};

const manifest = {
  id: 'community.qmh',
  version: '1.0.0',
  name: 'QMH Stream',
  description: 'Xem video clip QMH trực tiếp trên Stremio không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['qmh:'],
  catalogs: [
    {
      type: 'movie',
      id: 'qmh-catalog',
      name: 'QMH Cập Nhật',
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
    if (type !== 'movie' || id !== 'qmh-catalog') {
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
      poster: v.poster || `${host}/thumb/qmh/${v.rawId}.jpg`,
      background: v.poster || `${host}/thumb/qmh/${v.rawId}.jpg`,
      posterShape: 'landscape',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('QMH catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('qmh:')) {
      return { meta: null };
    }

    const rawId = id.replace('qmh:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const poster = details.poster || `${host}/thumb/qmh/${rawId}.jpg`;

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
    console.error('QMH meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('qmh:')) {
      return { streams: [] };
    }

    const rawId = id.replace('qmh:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'QMH',
        title: 'Server #1 (Full HD M3U8 - Không quảng cáo)',
        url: `${host}/qmh/hls/${rawId}/master.m3u8`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('QMH stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
