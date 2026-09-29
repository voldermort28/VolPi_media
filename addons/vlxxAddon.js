const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/vlxx');

const manifest = {
  id: 'community.vlxx',
  version: '1.1.1',
  name: 'VLFilm Stream',
  description: 'Xem phim và video VLFilm trực tiếp trên Stremio không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['movie'],
  idPrefixes: ['vlxx:'],
  catalogs: [
    {
      type: 'movie',
      id: 'vlxx-catalog',
      name: 'VLFilm Mới Cập Nhật',
      extra: [
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
    if (type !== 'movie' || id !== 'vlxx-catalog') {
      return { metas: [] };
    }

    const skip = (extra && extra.skip) ? parseInt(extra.skip, 10) : 0;
    const page = Math.floor(skip / 30) + 1;

    let videos = [];
    if (extra && extra.search) {
      videos = await scraper.search(extra.search, page);
    } else {
      videos = await scraper.getLatest(page);
    }

    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';
    const metas = videos.map((v) => ({
      id: v.id,
      name: v.title,
      poster: `${host}/thumb/vlxx/${v.rawId}.jpg`,
      background: `${host}/thumb/vlxx/${v.rawId}.jpg`,
      posterShape: 'landscape',
      type: 'movie',
      description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
    }));

    return { metas };
  } catch (err) {
    console.error('VLXX catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('vlxx:')) {
      return { meta: null };
    }

    const rawId = id.replace('vlxx:', '');
    const details = await scraper.getVideoDetails(rawId);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    return {
      meta: {
        id: details.id,
        name: details.name,
        poster: `${host}/thumb/vlxx/${rawId}.jpg`,
        background: `${host}/thumb/vlxx/${rawId}.jpg`,
        posterShape: 'landscape',
        description: details.description,
        genres: details.genres,
        cast: details.cast,
        type: 'movie',
      },
    };
  } catch (err) {
    console.error('VLXX meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (type !== 'movie' || !id.startsWith('vlxx:')) {
      return { streams: [] };
    }

    const rawId = id.replace('vlxx:', '');
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const streams = [
      {
        name: 'VLFilm',
        title: 'Server #1 (HD 1080p - No Ads)',
        url: `${host}/hls/${rawId}/1/master.m3u8`,
      },
      {
        name: 'VLFilm',
        title: 'Server #2 (HD 1080p - No Ads)',
        url: `${host}/hls/${rawId}/2/master.m3u8`,
      },
    ];

    return { streams };
  } catch (err) {
    console.error('VLXX stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
