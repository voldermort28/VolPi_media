const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/xoilac');

const manifest = {
  id: 'community.xoilac',
  version: '1.1.1',
  name: 'Xôi Lạc TV - Trực Tiếp Bóng Đá',
  description: 'Xem trực tiếp bóng đá mọi giải đấu từ Xôi Lạc TV với bình luận tiếng Việt không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['tv', 'movie'],
  idPrefixes: ['xoilac:'],
  catalogs: [
    {
      type: 'tv',
      id: 'xoilac-catalog',
      name: 'Trực Tiếp Bóng Đá (Xôi Lạc)',
      extra: [
        { name: 'search', isRequired: false },
      ],
    },
  ],
};

const builder = new addonBuilder(manifest);

builder.defineCatalogHandler(async (args) => {
  try {
    const { id, extra } = args;
    if (id !== 'xoilac-catalog') {
      return { metas: [] };
    }

    let matches = [];
    if (extra && extra.search) {
      matches = await scraper.searchMatches(extra.search);
    } else {
      matches = await scraper.getLiveMatches();
    }

    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    const metas = matches.map((m) => ({
      id: m.id,
      name: m.title,
      poster: `${host}/thumb/xoilac/${m.slug}.svg`,
      background: `${host}/thumb/xoilac/${m.slug}.svg`,
      posterShape: 'landscape',
      type: 'tv',
      description: `🏆 ${m.league} • ⏱️ ${m.time}\n⚽ ${m.homeTeam} vs ${m.awayTeam}`,
    }));

    return { metas };
  } catch (err) {
    console.error('Xôi Lạc catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (!id.startsWith('xoilac:')) {
      return { meta: null };
    }

    const slug = id.replace('xoilac:', '');
    const details = await scraper.getMatchDetails(slug);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    return {
      meta: {
        id: details.id,
        name: details.name,
        poster: `${host}/thumb/xoilac/${slug}.svg`,
        background: `${host}/thumb/xoilac/${slug}.svg`,
        posterShape: 'landscape',
        description: details.description,
        genres: details.genres,
        type: type || 'tv',
      },
    };
  } catch (err) {
    console.error('Xôi Lạc meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { id } = args;
    if (!id.startsWith('xoilac:')) {
      return { streams: [] };
    }

    const slug = id.replace('xoilac:', '');
    const streams = await scraper.getMatchStreams(slug);

    return { streams };
  } catch (err) {
    console.error('Xôi Lạc stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
