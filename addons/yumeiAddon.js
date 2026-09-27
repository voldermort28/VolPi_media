const { addonBuilder } = require('stremio-addon-sdk');
const scraper = require('../scrapers/yumei');

const manifest = {
  id: 'community.yumeianime.v3',
  version: '3.6.3',
  name: 'VolPi Media - Yumei Anime',
  description: 'Kho phim Anime Vietsub, Pokemon, Super Sentai & Power Rangers Full HD',
  resources: ['catalog', 'meta', 'stream'],
  types: ['series', 'movie'],
  idPrefixes: ['yumei:'],
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
  ],
};

const builder = new addonBuilder(manifest);

// Catalog Handler
builder.defineCatalogHandler(async (args) => {
  try {
    const { type, id, extra } = args;
    const metas = await scraper.getCatalog(id, extra, type);
    return { metas };
  } catch (err) {
    console.error('Yumei catalog error:', err);
    return { metas: [] };
  }
});

// Meta Handler
builder.defineMetaHandler(async (args) => {
  try {
    const { type, id } = args;
    if (!id.startsWith('yumei:')) {
      return { meta: null };
    }

    if (id.startsWith('yumei:m:') || id.startsWith('yumei:movie:')) {
      const movieMeta = await scraper.getMovieMeta(id, type);
      return { meta: movieMeta };
    }

    const seriesMeta = await scraper.getSeriesMeta(id, type);
    return { meta: seriesMeta };
  } catch (err) {
    console.error('Yumei meta error:', err);
    return { meta: null };
  }
});

// Stream Handler
builder.defineStreamHandler(async (args) => {
  try {
    const { type, id } = args;
    if (!id.startsWith('yumei:')) {
      return { streams: [] };
    }

    const streams = await scraper.getStreams(id);
    return { streams };
  } catch (err) {
    console.error('Yumei stream error:', err);
    return { streams: [] };
  }
});

module.exports = builder.getInterface();
