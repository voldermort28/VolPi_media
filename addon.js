const { addonBuilder } = require('stremio-addon-sdk');
const vlxxScraper = require('./scrapers/vlxx');
const xoilacScraper = require('./scrapers/xoilac');
const socoliveScraper = require('./scrapers/socolive');
const yumeiScraper = require('./scrapers/yumei');

const manifest = {
  id: 'community.vnstream.v3',
  version: '3.7.0',
  name: 'VolPi Media',
  description: 'Addon tổng hợp xem Anime Vietsub (Pokemon, Tokusatsu, Super Sentai, Power Rangers), Trực tiếp bóng đá Xôi Lạc TV & Socolive TV và Phim VLFilm',
  resources: ['catalog', 'meta', 'stream'],
  types: ['series', 'movie', 'tv'],
  idPrefixes: ['vlxx:', 'xoilac:', 'socolive:', 'yumei:'],
  catalogs: [
    // --- SERIES CATALOGS (Chỉ Phim Bộ) ---
    {
      type: 'series',
      id: 'yumei-top',
      name: '🌟 Thư Viện Yumei (4 Danh Mục Thế Giới)',
      extra: [
        {
          name: 'genre',
          options: [
            'Tất cả',
            '🌟 4 Danh Mục Thế Giới',
            '🔴 Pokemon (5 Phân Mục)',
            '⚡ Super Sentai (18 Series)',
            '⚡ Power Rangers (2 Nhóm Phim)',
            '🌸 Anime Khác (6 Series)',
          ],
          isRequired: false,
        },
        { name: 'search', isRequired: false },
      ],
    },
    {
      type: 'series',
      id: 'yumei-pokemon',
      name: '🔴 Pokemon (5 Phân Mục Chính)',
      extra: [
        {
          name: 'genre',
          options: [
            'Tất cả',
            'TV Series (29 mùa)',
            'Horizons (8 chương)',
            'The Movies (25 phim)',
            'TV Specials (56 tập)',
            'Pikachu Shorts (26 tập)',
          ],
          isRequired: false,
        },
        { name: 'search', isRequired: false },
      ],
    },
    {
      type: 'series',
      id: 'yumei-tokusatsu',
      name: '⚡ Super Sentai (18 Series Siêu Nhân)',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'series',
      id: 'yumei-power-rangers',
      name: '⚡ Power Rangers (2 Nhóm Phim)',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'series',
      id: 'yumei-anime',
      name: '🌸 Anime Khác (6 Series Tuổi Thơ)',
      extra: [{ name: 'search', isRequired: false }],
    },

    // --- MOVIE CATALOGS (Chỉ Phim Lẻ / Chiếu Rạp) ---
    {
      type: 'movie',
      id: 'yumei-movies-all',
      name: '🎬 Yumei Phim Điện Ảnh (Tất Cả Movies)',
      extra: [
        {
          name: 'genre',
          options: [
            'Tất cả',
            '🔴 Pokemon The Movies',
            '⚡ Super Sentai The Movies',
            '⚡ Power Rangers The Movies',
          ],
          isRequired: false,
        },
        { name: 'search', isRequired: false },
      ],
    },
    {
      type: 'movie',
      id: 'yumei-pokemon-movies',
      name: '🔴 Pokemon The Movies (25 Phim Chiếu Rạp)',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'movie',
      id: 'yumei-sentai-movies',
      name: '⚡ Super Sentai The Movies (18+ Phim Điện Ảnh & Specials)',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'movie',
      id: 'yumei-power-rangers-movies',
      name: '⚡ Power Rangers & Tokusatsu The Movies',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'movie',
      id: 'vlxx-catalog',
      name: 'VLFilm Mới Cập Nhật',
      extra: [
        { name: 'search', isRequired: false },
        { name: 'skip', isRequired: false },
      ],
    },

    // --- TV CATALOGS ---
    {
      type: 'tv',
      id: 'xoilac-catalog',
      name: 'Trực Tiếp Bóng Đá (Xôi Lạc)',
      extra: [{ name: 'search', isRequired: false }],
    },
    {
      type: 'tv',
      id: 'socolive-catalog',
      name: 'Trực Tiếp Bóng Đá (Socolive)',
      extra: [{ name: 'search', isRequired: false }],
    },
  ],
};

const builder = new addonBuilder(manifest);

builder.defineCatalogHandler(async (args) => {
  try {
    const { type, id, extra } = args;
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    if (id.startsWith('yumei-')) {
      const metas = await yumeiScraper.getCatalog(id, extra, type);
      return { metas };
    }

    if (id === 'vlxx-catalog') {
      const skip = extra && extra.skip ? parseInt(extra.skip, 10) : 0;
      const page = Math.floor(skip / 30) + 1;
      let videos = [];
      if (extra && extra.search) {
        videos = await vlxxScraper.search(extra.search, page);
      } else {
        videos = await vlxxScraper.getLatest(page);
      }
      return {
        metas: videos.map((v) => ({
          id: v.id,
          name: v.title,
          poster: `${host}/thumb/vlxx/${v.rawId}.jpg`,
          background: `${host}/thumb/vlxx/${v.rawId}.jpg`,
          posterShape: 'landscape',
          type: 'movie',
          description: v.ribbon ? `[${v.ribbon}] ${v.title}` : v.title,
        })),
      };
    }

    if (id === 'xoilac-catalog') {
      let matches = [];
      if (extra && extra.search) {
        matches = await xoilacScraper.searchMatches(extra.search);
      } else {
        matches = await xoilacScraper.getLiveMatches();
      }
      return {
        metas: matches.map((m) => ({
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
          poster: `${host}/thumb/xoilac/${m.slug}.svg`,
          background: `${host}/thumb/xoilac/${m.slug}.svg`,
          posterShape: 'landscape',
          type: 'tv',
          description: `🏆 ${m.league} • ⏱️ ${m.time}\n⚽ ${m.homeTeam} vs ${m.awayTeam}`,
        })),
      };
    }

    if (id === 'socolive-catalog') {
      let matches = [];
      if (extra && extra.search) {
        matches = await socoliveScraper.searchMatches(extra.search);
      } else {
        matches = await socoliveScraper.getLiveMatches();
      }
      return {
        metas: matches.map((m) => ({
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
        })),
      };
    }

    return { metas: [] };
  } catch (err) {
    console.error('Catalog handler error:', err);
    return { metas: [] };
  }
});

builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

    if (id.startsWith('yumei:')) {
      if (id.startsWith('yumei:m:') || id.startsWith('yumei:movie:')) {
        const movieMeta = await yumeiScraper.getMovieMeta(id, type);
        return { meta: movieMeta };
      }
      const seriesMeta = await yumeiScraper.getSeriesMeta(id, type);
      return { meta: seriesMeta };
    }

    if (id.startsWith('vlxx:')) {
      const rawId = id.replace('vlxx:', '');
      const details = await vlxxScraper.getVideoDetails(rawId);
      const meta = {
        id: details.id,
        name: details.name,
        poster: `${host}/thumb/vlxx/${rawId}.jpg`,
        background: `${host}/thumb/vlxx/${rawId}.jpg`,
        posterShape: 'landscape',
        description: details.description,
        genres: details.genres,
        cast: details.cast,
        type: type || 'movie',
      };
      if (type === 'series') {
        meta.videos = [
          {
            id: details.id,
            name: details.name,
            season: 1,
            episode: 1,
            number: 1,
            released: '2020-01-01T00:00:00.000Z',
          },
        ];
      }
      return { meta };
    }

    if (id.startsWith('xoilac:')) {
      const slug = id.replace('xoilac:', '');
      const details = await xoilacScraper.getMatchDetails(slug);
      return {
        meta: {
          id: details.id,
          name: details.name,
          poster: `${host}/thumb/xoilac/${slug}.svg`,
          background: `${host}/thumb/xoilac/${slug}.svg`,
          posterShape: 'landscape',
          description: details.description,
          genres: details.genres,
          type: 'tv',
        },
      };
    }

    if (id.startsWith('socolive:')) {
      const slug = id.replace('socolive:', '');
      const details = await socoliveScraper.getMatchDetails(slug);
      return {
        meta: {
          id: details.id,
          name: details.name,
          poster: `${host}/thumb/socolive/${slug}.svg`,
          background: `${host}/thumb/socolive/${slug}.svg`,
          posterShape: 'landscape',
          description: details.description,
          genres: details.genres,
          type: 'tv',
        },
      };
    }

    return { meta: null };
  } catch (err) {
    console.error('Meta handler error:', err);
    return { meta: null };
  }
});

builder.defineStreamHandler(async (args) => {
  try {
    const { id } = args;

    if (id.startsWith('yumei:')) {
      const streams = await yumeiScraper.getStreams(id);
      return { streams };
    }

    if (id.startsWith('vlxx:')) {
      const rawId = id.replace('vlxx:', '');
      const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';
      return {
        streams: [
          {
            name: 'VLFilm',
            title: 'Server #1 (HD 1080p - No Ads)',
            url: `${host}/hls/${rawId}/1/master.m3u8`,
            behaviorHints: {
              notWebReady: false,
            },
          },
          {
            name: 'VLFilm',
            title: 'Server #2 (HD 1080p - No Ads)',
            url: `${host}/hls/${rawId}/2/master.m3u8`,
            behaviorHints: {
              notWebReady: false,
            },
          },
        ],
      };
    }

    if (id.startsWith('xoilac:')) {
      const slug = id.replace('xoilac:', '');
      const streams = await xoilacScraper.getMatchStreams(slug);
      return { streams };
    }

    if (id.startsWith('socolive:')) {
      const slug = id.replace('socolive:', '');
      const streams = await socoliveScraper.getMatchStreams(slug);
      return { streams };
    }

    return { streams: [] };
  } catch (err) {
    console.error('Stream handler error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
