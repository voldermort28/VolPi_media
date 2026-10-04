const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/socolive');

const manifest = {
  id: 'community.socolive',
  version: '1.0.0',
  name: 'Socolive TV - Trực Tiếp Bóng Đá',
  description: 'Xem trực tiếp bóng đá mọi giải đấu từ Socolive TV với bình luận tiếng Việt không quảng cáo',
  resources: ['catalog', 'meta', 'stream'],
  types: ['tv', 'movie'],
  idPrefixes: ['socolive:'],
  catalogs: [
    {
      type: 'tv',
      id: 'socolive-catalog',
      name: 'Trực Tiếp Bóng Đá (Socolive)',
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
    if (id !== 'socolive-catalog') {
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
      homeTeam: m.homeTeam,
      awayTeam: m.awayTeam,
      homeLogo: m.homeLogo,
      awayLogo: m.awayLogo,
      league: m.league,
      time: m.time,
      priority: m.priority,
      isFamous: m.isFamous,
      isVietnam: m.isVietnam,
      isLive: m.isLive,
      matchTimestamp: m.matchTimestamp,
      poster: `${host}/thumb/socolive/${m.slug}.svg`,
      background: `${host}/thumb/socolive/${m.slug}.svg`,
      posterShape: 'landscape',
      type: 'tv',
      description: `🏆 ${m.league} • ⏱️ ${m.time}\n⚽ ${m.homeTeam} vs ${m.awayTeam}`,
    }));

    return { metas };
  } catch (err) {
    console.error('Socolive catalog error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (!id.startsWith('socolive:')) {
      return { meta: null };
    }

    const slug = id.replace('socolive:', '');
    const details = await scraper.getMatchDetails(slug);
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    return {
      meta: {
        id: details.id,
        name: details.name,
        poster: `${host}/thumb/socolive/${slug}.svg`,
        background: `${host}/thumb/socolive/${slug}.svg`,
        posterShape: 'landscape',
        description: details.description,
        genres: details.genres,
        type: type || 'tv',
      },
    };
  } catch (err) {
    console.error('Socolive meta error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { id } = args;
    if (!id.startsWith('socolive:')) {
      return { streams: [] };
    }

    const slug = id.replace('socolive:', '');
    const streams = await scraper.getMatchStreams(slug);

    return { streams };
  } catch (err) {
    console.error('Socolive stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
