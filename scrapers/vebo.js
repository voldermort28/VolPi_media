const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().veboBaseUrl || 'https://vebozbn.cc';
}

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const MOBILE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

let cachedMatches = [];
let lastCacheTime = 0;

function clearCache() {
  cachedMatches = [];
  lastCacheTime = 0;
  resolvedBaseUrl = null;
}

// Vietnam clubs, national teams & tournament keywords
const VIETNAM_KEYWORDS = [
  'việt nam', 'viet nam', 'vietnam', 'đt việt nam', 'đội tuyển việt nam', 'tuyển việt nam',
  'u23 việt nam', 'u22 việt nam', 'u21 việt nam', 'u20 việt nam', 'u19 việt nam', 'u17 việt nam', 'u16 việt nam',
  'nữ việt nam', 'futsal việt nam',
  'v-league', 'vleague', 'v.league', 'v league', 'cúp quốc gia', 'cúp qg việt nam', 'siêu cúp quốc gia',
  'hạng nhất quốc gia', 'hạng nhì quốc gia', 'aff cup', 'aff suzuki', 'mitsubishi electric',
  'asean cup', 'asean championship', 'shopee cup', 'asean club',
  'nam định', 'thép xanh nam định', 'hà nội fc', 'clb hà nội', 'công an hà nội', 'cahn',
  'thể công', 'viettel', 'hagl', 'hoàng anh gia lai', 'sông lam nghệ an', 'slna',
  'thanh hóa', 'đông á thanh hóa', 'bình định', 'quy nhơn bình định', 'hải phòng',
  'bình dương', 'becamex', 'tp.hồ chí minh', 'tp hcm', 'tphcm', 'đà nẵng', 'shb đà nẵng',
  'quảng nam', 'hà tĩnh', 'hồng lĩnh hà tĩnh', 'khánh hòa', 'bình phước', 'trường tươi',
  'ninh bình', 'phù đổng', 'long an', 'bà rịa vũng tàu', 'đồng tháp', 'hòa bình'
];

// Major prominent leagues & tournaments
const MAJOR_LEAGUE_KEYWORDS = [
  'ngoại hạng anh', 'english premier league', 'fa cup', 'cúp fa', 'carabao', 'efl cup', 'cúp liên đoàn anh',
  'champions league', 'cúp c1', 'uefa champions', 'ucl',
  'europa league', 'cúp c2', 'uefa europa', 'uel',
  'conference league', 'cúp c3', 'uefa conference', 'uecl',
  'siêu cúp châu âu', 'super cup',
  'la liga', 'vđqg tây ban nha', 'copa del rey', 'cúp nhà vua', 'supercopa',
  'serie a', 'vđqg ý', 'coppa italia', 'cúp ý', 'supercoppa italiana',
  'bundesliga', 'vđqg đức', 'dfb-pokal', 'cúp qg đức', 'dfl-supercup',
  'ligue 1', 'vđqg pháp', 'coupe de france', 'cúp qg pháp',
  'world cup', 'vòng loại world cup', 'uefa euro', 'vòng loại euro', 'euro 2024', 'euro 2028', 'cúp euro',
  'nations league', 'copa america', 'asian cup', 'afc champions league', 'cúp c1 châu á', 'cúp c2 châu á',
  'afcon', 'cúp châu phi', 'african cup',
  'concacaf', 'gold cup',
  'saudi pro league', 'saudi league', 'vđqg ả rập xê út', 'mls', 'major league soccer', 'nhà nghề mỹ'
];

// Major clubs
const MAJOR_CLUB_KEYWORDS = [
  'manchester united', 'man utd', 'manchester utd', 'm.u', 'mu fc',
  'arsenal', 'chelsea', 'liverpool', 'manchester city', 'man city', 'tottenham', 'spurs', 'newcastle', 'aston villa',
  'real madrid', 'barcelona', 'barca', 'atletico madrid', 'sevilla',
  'bayern munich', 'bayern munchen', 'dortmund', 'bayer leverkusen',
  'juventus', 'inter milan', 'ac milan', 'napoli', 'roma', 'lazio',
  'paris saint-germain', 'psg', 'marseille', 'lyon',
  'al nassr', 'al hilal', 'al ittihad', 'inter miami'
];

function isVietnamMatch(allText) {
  const t = allText.toLowerCase();
  return VIETNAM_KEYWORDS.some((k) => t.includes(k));
}

function isMuMatch(allText) {
  const t = allText.toLowerCase();
  return t.includes('manchester united') ||
         t.includes('manchester utd') ||
         t.includes('man utd') ||
         /\bmu\b/.test(t) ||
         t.includes('m.u');
}

function isPremierLeagueOrC1(league, title, isVn = false) {
  const t = `${league || ''} ${title || ''}`.toLowerCase();

  const isWomen = (t.includes('women') || t.includes('nữ')) && !isVn;
  if (isWomen) return false;

  const isYouthOrReserve = (t.includes('u17') || t.includes('u18') || t.includes('u19') || t.includes('u21') || t.includes('reserve') || t.includes('youth') || t.includes('trẻ')) && !isVn;
  if (isYouthOrReserve) return false;

  const isOtherConfederation = t.includes('caf') ||
      t.includes('africa') ||
      t.includes('châu phi') ||
      t.includes('concacaf') ||
      t.includes('bắc mỹ') ||
      t.includes('afc') ||
      t.includes('châu á') ||
      t.includes('ofc');

  const isC1 = !isOtherConfederation && (
    t.includes('uefa champions') ||
    t.includes('cúp c1') ||
    t.includes('c1 châu âu') ||
    /\bucl\b/.test(t) ||
    t.includes('champions league')
  );

  const nonEnglish = [
    'kuwait', 'ai cập', 'egypt', 'belarus', 'nga', 'russia', 'scotland', 'israel',
    'ukraine', 'ireland', 'wales', 'canada', 'úc', 'australia', 'kazakhstan',
    'singapore', 'thái', 'thai', 'indo', 'ấn độ', 'india', 'nam phi', 'hàn quốc',
    'korea', 'qatar', 'uae', 'saudi', 'iraq', 'armenia', 'georgia', 'azerbaijan',
    'mongolia', 'mông cổ', 'hong kong', 'bắc ireland', 'northern ireland', 'cymru'
  ];

  const isEpl = (t.includes('premier league') || t.includes('ngoại hạng anh') || /\bepl\b/.test(t) || t.includes('english premier league')) &&
                !nonEnglish.some((c) => t.includes(c));

  return isC1 || isEpl;
}

function isMajorLeague(league, home, away, title, isVn = false) {
  const t = `${league || ''} ${home || ''} ${away || ''} ${title || ''}`.toLowerCase();
  if (isVn) return true;
  if (isMuMatch(t)) return true;
  if (isPremierLeagueOrC1(league, title, isVn)) return true;

  const isExcluded = (t.includes('u17') || t.includes('u19') || t.includes('u21') || t.includes('women') || t.includes('nữ') || t.includes('hạng 2') || t.includes('hạng 3') || t.includes('division 2') || t.includes('reserve')) && !isVn;
  if (isExcluded) return false;

  if (MAJOR_LEAGUE_KEYWORDS.some((k) => t.includes(k))) return true;
  if (MAJOR_CLUB_KEYWORDS.some((k) => t.includes(k))) return true;
  return false;
}

function isGrassLeague(m) {
  if (m.isVietnam) return false;
  if (m.isMu || m.isMuFavorite) return false;
  if (m.isPremierLeagueOrC1) return false;
  if (m.isMajor) return false;
  if (m.isHot) return false;
  if (m.isFamous) return false;
  return true;
}

function getGroupRank(m) {
  if (m.isFinished) return 3;
  if (isGrassLeague(m)) return 2;
  return 1;
}

function getImportanceScore(m) {
  if (m.isMu || m.isMuFavorite) return 10;
  if (m.isVietnam) return 20;
  if (m.isPremierLeagueOrC1) return 30;
  if (m.isHot) return 40;
  if (m.isMajor || m.isFamous) return 50;
  return 70;
}

function calculateMatchScore(m) {
  return getGroupRank(m) * 100 + getImportanceScore(m);
}

function sortMatches(matches) {
  matches.sort((a, b) => {
    // 1. Group Rank: Main matches (1) -> Grass leagues (2) -> Finished (3)
    const gA = getGroupRank(a);
    const gB = getGroupRank(b);
    if (gA !== gB) return gA - gB;

    // 2. Ongoing/Live matches first
    const ongoingA = a.isLive ? 0 : 1;
    const ongoingB = b.isLive ? 0 : 1;
    if (ongoingA !== ongoingB) return ongoingA - ongoingB;

    // 3. Chronological schedule from nearest to furthest (từ gần nhất đến xa nhất)
    const tA = a.matchTimestamp || 0;
    const tB = b.matchTimestamp || 0;
    if (tA > 0 && tB > 0 && tA !== tB) {
      return tA - tB;
    }
    if (tA > 0 && tB <= 0) return -1;
    if (tA <= 0 && tB > 0) return 1;

    // 4. Same time: More important matches first
    const impA = getImportanceScore(a);
    const impB = getImportanceScore(b);
    if (impA !== impB) return impA - impB;

    return 0;
  });
}

function parseVeboMatchItem($, el, hotIdsSet = new Set()) {
  const $card = $(el);
  const fid = $card.attr('data-fid') || '';
  if (!fid) return null;

  const rawHot = $card.attr('data-hot') || '';
  const cardClass = $card.attr('class') || '';
  const isHot = hotIdsSet.has(fid) || rawHot.includes('on') || rawHot === '1' || cardClass.includes('grid-match--is-hot');

  const league = ($card.attr('data-league') || $card.find('.gmd-match-league span').text() || 'Bóng đá').trim();
  const rawRuntime = $card.attr('data-runtime');
  let ts = 0;
  if (rawRuntime) {
    const num = parseInt(rawRuntime, 10);
    if (!isNaN(num) && num > 0) {
      ts = num * 1000;
    }
  }

  const statusVal = $card.attr('data-status') || '';
  // 1: upcoming, 2: 1st half, 3: halftime, 4: 2nd half, 5: extra, -1: finished
  const isLive = statusVal === '2' || statusVal === '3' || statusVal === '4' || statusVal === '5' || cardClass.includes('is-live');
  const isFinished = statusVal === '-1' || (ts > 0 && !isLive && (Date.now() - ts) > 115 * 60 * 1000);

  const homeTeam = $card.find('.gmd-home_team p').text().trim();
  const awayTeam = $card.find('.gmd-away_team p').text().trim();
  if (!homeTeam || !awayTeam) return null;

  const homeLogo = $card.find('.gmd-home_team img').attr('src') || '';
  const awayLogo = $card.find('.gmd-away_team img').attr('src') || '';

  const time = $card.find('.gmd-match-date span').text().trim() || $card.find('.t_time').attr('data-time') || '';
  const score = $card.find('.gmd-mid_score .gmd-score-box').text().trim();

  // Extract slug from redirect link
  let href = $card.find('a.redirectPopup').attr('href') || $card.find('a').attr('href') || '';
  let slug = fid;
  if (href) {
    const m = href.match(/\/truc-tiep\/([^\/]+)/);
    if (m && m[1]) {
      slug = m[1];
    }
  }

  const title = `${homeTeam} vs ${awayTeam}`;
  const allText = `${title} ${league} ${homeTeam} ${awayTeam}`;

  const isVn = isVietnamMatch(allText);
  const isMu = isMuMatch(allText);
  const isPlOrC1 = isPremierLeagueOrC1(league, title, isVn);
  const isMajor = isMajorLeague(league, homeTeam, awayTeam, title, isVn);

  const matchObj = {
    id: `vebo:${slug}`,
    slug,
    fid,
    title,
    homeTeam,
    awayTeam,
    homeLogo,
    awayLogo,
    league,
    time,
    matchTimestamp: ts,
    isLive,
    isFinished,
    isHot,
    isVietnam: isVn,
    isMu,
    isMuFavorite: isMu,
    isPremierLeagueOrC1: isPlOrC1,
    isFamous: isMajor,
    isMajor,
    score: score.replace(/\s+/g, ' '),
    poster: homeLogo || awayLogo,
    source: 'vebo',
  };

  matchObj.priorityScore = calculateMatchScore(matchObj);
  return matchObj;
}

async function getLiveMatches() {
  if (Date.now() - lastCacheTime < 60000 && cachedMatches.length > 0) {
    return cachedMatches;
  }

  const baseUrl = getBaseUrl();
  const matchesMap = new Map();
  const hotIdsSet = new Set();

  // 1. Fetch Hot Matches endpoint from Vebo (/sport/football/filter/hot)
  try {
    const hotUrl = `${baseUrl}/sport/football/filter/hot`;
    const hotRes = await axios.get(hotUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Referer': baseUrl,
      },
      timeout: 10000,
    });

    if (hotRes.data && hotRes.data.success && hotRes.data.data && Array.isArray(hotRes.data.data.htmls)) {
      hotRes.data.data.htmls.forEach((htmlChunk) => {
        const $chunk = cheerio.load(htmlChunk);
        $chunk('.match-football-item').each((_, el) => {
          const fid = $chunk(el).attr('data-fid');
          if (fid) hotIdsSet.add(fid);

          const m = parseVeboMatchItem($chunk, el, hotIdsSet);
          if (m && !matchesMap.has(m.slug)) {
            matchesMap.set(m.slug, m);
          }
        });
      });
    }
  } catch (err) {
    console.error('Vebo filter/hot fetch error:', err.message);
  }

  // 2. Fetch Homepage to get all matches
  try {
    const homeRes = await axios.get(baseUrl, {
      headers: {
        'User-Agent': USER_AGENT,
      },
      timeout: 10000,
    });

    const $ = cheerio.load(homeRes.data);
    $('.match-football-item').each((_, el) => {
      const m = parseVeboMatchItem($, el, hotIdsSet);
      if (m && !matchesMap.has(m.slug)) {
        matchesMap.set(m.slug, m);
      }
    });
  } catch (err) {
    console.error('Vebo homepage scrape error:', err.message);
  }

  const matches = Array.from(matchesMap.values());

  // 3. Sort matches: Main matches (nearest to furthest) -> Grass leagues (nearest to furthest) -> Finished
  sortMatches(matches);

  if (matches.length > 0) {
    cachedMatches = matches;
    lastCacheTime = Date.now();
  }

  return matches;
}

async function getMatchDetails(slug) {
  const allMatches = await getLiveMatches();
  const matchInfo = allMatches.find((m) => m.slug === slug);

  if (matchInfo) {
    return {
      id: `vebo:${slug}`,
      slug,
      name: matchInfo.title,
      time: matchInfo.time,
      league: matchInfo.league,
      homeTeam: matchInfo.homeTeam,
      awayTeam: matchInfo.awayTeam,
      homeLogo: matchInfo.homeLogo,
      awayLogo: matchInfo.awayLogo,
      description: `🏆 Giải đấu: ${matchInfo.league}\n⏱️ Thời gian: ${matchInfo.time}\n⚽ Trận đấu: ${matchInfo.homeTeam} vs ${matchInfo.awayTeam}\n📺 Trực tiếp từ Về Bờ TV với bình luận tiếng Việt.`,
      genres: [matchInfo.league, 'Trực Tiếp Bóng Đá', 'Về Bờ TV'],
      type: 'tv',
      isHot: matchInfo.isHot,
      isVietnam: matchInfo.isVietnam,
      isLive: matchInfo.isLive,
    };
  }

  return {
    id: `vebo:${slug}`,
    slug,
    name: `Trận đấu ${slug.replace(/-/g, ' ')}`,
    description: 'Trực tiếp từ Về Bờ TV',
    genres: ['Trực Tiếp Bóng Đá', 'Về Bờ TV'],
    type: 'tv',
  };
}

async function getMatchStreams(slug) {
  const baseUrl = getBaseUrl();
  const matchPageUrl = `${baseUrl}/truc-tiep/${slug}/`;
  const streams = [];
  const seenUrls = new Set();

  try {
    const res = await axios.get(matchPageUrl, {
      headers: {
        'User-Agent': USER_AGENT,
      },
      timeout: 10000,
    });

    const html = res.data;
    const $ = cheerio.load(html);

    // 1. Extract BLV channel labels from .player-link
    const channelNames = [];
    $('.player-link').each((i, el) => {
      const name = $(el).text().replace(/\s+/g, ' ').trim() || `Kênh ${i + 1}`;
      channelNames.push(name);
    });

    // 2. Extract list_stream JavaScript array
    const streamMatch = html.match(/var\s+list_stream\s*=\s*(\[[\s\S]*?\]);/);
    let listStream = [];
    if (streamMatch) {
      try {
        listStream = JSON.parse(streamMatch[1].replace(/\\/g, ''));
      } catch (e) {
        // Fallback eval / clean parse
        const cleanJson = streamMatch[1].replace(/\\\//g, '/');
        try {
          listStream = JSON.parse(cleanJson);
        } catch (e2) {}
      }
    }

    // 3. For each stream channel, fetch the iframe with iOS User-Agent to extract m3u8
    for (let i = 0; i < listStream.length; i++) {
      const channelUrls = listStream[i];
      if (!Array.isArray(channelUrls) || channelUrls.length === 0) continue;

      const iframeUrl = channelUrls[0];
      const channelLabel = channelNames[i] || `Kênh ${i + 1}`;

      try {
        const iframeRes = await axios.get(iframeUrl, {
          headers: {
            'User-Agent': MOBILE_UA,
            'Referer': matchPageUrl,
          },
          timeout: 7000,
        });

        const iframeHtml = iframeRes.data;
        const m3u8Match = iframeHtml.match(/var\s+urlStream\s*=\s*"([^"]+)";/);

        if (m3u8Match && m3u8Match[1]) {
          const streamUrl = m3u8Match[1];
          if (!seenUrls.has(streamUrl)) {
            seenUrls.add(streamUrl);
            const labelFormatted = channelLabel.toUpperCase().includes('BLV') ? channelLabel : `BLV ${channelLabel}`;

            streams.push({
              name: `Về Bờ • ${labelFormatted}`,
              title: `${labelFormatted} - Trực Tiếp (Full HD)`,
              url: streamUrl,
              headers: {
                'Referer': baseUrl,
                'User-Agent': MOBILE_UA,
                'Origin': baseUrl,
              },
              behaviorHints: {
                notWebReady: false,
                proxyHeaders: {
                  request: {
                    'Referer': baseUrl,
                    'User-Agent': MOBILE_UA,
                    'Origin': baseUrl,
                  },
                },
              },
            });
          }
        }
      } catch (iframeErr) {
        // Ignore single iframe error and continue to other channels
      }
    }
  } catch (pageErr) {
    console.error('Vebo match detail scrape error:', pageErr.message);
  }

  return streams;
}

module.exports = {
  getBaseUrl,
  getLiveMatches,
  getMatchDetails,
  getMatchStreams,
  clearCache,
  USER_AGENT,
  calculateMatchScore,
};
