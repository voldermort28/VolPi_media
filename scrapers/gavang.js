const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().gavangBaseUrl || 'https://gavang1.xyz';
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

  // Exclude youth/reserve and non-VN women from major leagues
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

async function getLiveMatches() {
  if (Date.now() - lastCacheTime < 60000 && cachedMatches.length > 0) {
    return cachedMatches;
  }

  const baseUrl = getBaseUrl();
  let matches = [];

  // 1. Try REST API endpoint first
  try {
    const apiUrl = `${baseUrl}/wp-json/gavang33live/v1/matches?gavang33live_v=2.0.13.24`;
    const res = await axios.get(apiUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Referer': baseUrl,
      },
      timeout: 10000,
    });

    if (res.data && res.data.success && Array.isArray(res.data.data)) {
      const dataList = res.data.data;
      dataList.forEach((item) => {
        const slug = item.slug || item.match_id;
        const homeTeam = (item.home_name || '').trim();
        const awayTeam = (item.away_name || '').trim();
        const league = (item.competition || 'Bóng đá').trim();
        const time = (item.display_time || '').trim();
        const title = `${homeTeam} vs ${awayTeam}`;
        const allText = `${title} ${league} ${homeTeam} ${awayTeam}`;

        const isLive = item.status_kind === 'live';
        const isFinished = item.status_kind === 'finished';
        const isHot = Array.isArray(item.groups) && item.groups.includes('hot');

        const homeLogo = item.home_logo || '';
        const awayLogo = item.away_logo || '';

        const homeScore = item.home_score !== undefined ? String(item.home_score) : '';
        const awayScore = item.away_score !== undefined ? String(item.away_score) : '';
        const score = (homeScore && awayScore) ? `${homeScore} - ${awayScore}` : '';

        // Extract presenters / BLV
        const blvs = [];
        if (Array.isArray(item.presenters)) {
          item.presenters.forEach((p) => {
            if (p && p.name) {
              blvs.push({
                id: p.id || '',
                name: p.name,
                avatar: p.avatar || '',
                streamUrls: Array.isArray(p.streamUrls) ? p.streamUrls : [],
              });
            }
          });
        }

        const defaultLink = item.default_link || '';

        const isVn = isVietnamMatch(allText);
        const isMu = isMuMatch(allText);
        const isPlOrC1 = isPremierLeagueOrC1(league, title, isVn);
        const isMajor = isMajorLeague(league, homeTeam, awayTeam, title, isVn);

        const matchObj = {
          id: `gavang:${slug}`,
          slug,
          matchId: item.match_id || slug,
          title,
          homeTeam,
          awayTeam,
          homeLogo,
          awayLogo,
          league,
          time,
          matchTimestamp: item.timestamp ? item.timestamp * 1000 : 0,
          isLive,
          isFinished,
          isHot,
          isVietnam: isVn,
          isMu,
          isMuFavorite: isMu,
          isPremierLeagueOrC1: isPlOrC1,
          isFamous: isMajor,
          isMajor,
          score,
          blvs,
          defaultLink,
          poster: homeLogo || awayLogo,
          source: 'gavang',
        };

        matchObj.priorityScore = calculateMatchScore(matchObj);
        matches.push(matchObj);
      });
    }
  } catch (apiErr) {
    console.error('GaVang REST API failed, falling back to homepage scrape:', apiErr.message);
  }

  // 2. Fallback: Parse HTML if REST API returned empty
  if (matches.length === 0) {
    try {
      const res = await axios.get(baseUrl, {
        headers: {
          'User-Agent': USER_AGENT,
        },
        timeout: 10000,
      });

      const $ = cheerio.load(res.data);
      $('.tlvlc-match-card').each((_, el) => {
        const $card = $(el);
        const rawBootstrap = $card.attr('data-match-bootstrap');
        if (!rawBootstrap) return;

        try {
          const item = JSON.parse(rawBootstrap);
          const slug = item.slug || item.matchId;
          const homeTeam = (item.homeTeam && item.homeTeam.name ? item.homeTeam.name : '').trim();
          const awayTeam = (item.awayTeam && item.awayTeam.name ? item.awayTeam.name : '').trim();
          const league = (item.competition && item.competition.name ? item.competition.name : 'Bóng đá').trim();
          const time = (item.matchNormalizedDate || '').trim();
          const title = `${homeTeam} vs ${awayTeam}`;
          const allText = `${title} ${league} ${homeTeam} ${awayTeam}`;

          const isLive = item.matchStatus === 'live' || $card.hasClass('is-live');
          const isFinished = item.matchStatus === 'finished';
          const cardGroups = ($card.attr('data-groups') || '').split(' ');
          const isHot = cardGroups.includes('hot');

          const homeLogo = (item.homeTeam && item.homeTeam.logo) ? item.homeTeam.logo : '';
          const awayLogo = (item.awayTeam && item.awayTeam.logo) ? item.awayTeam.logo : '';

          const blvs = [];
          if (Array.isArray(item.anchorAppointmentVoList)) {
            item.anchorAppointmentVoList.forEach((a) => {
              if (a && a.nickName) {
                blvs.push({
                  id: a.id || '',
                  name: a.nickName,
                  avatar: a.userImage || '',
                  streamUrls: Array.isArray(a.streamUrls) ? a.streamUrls : [],
                });
              }
            });
          }

          const defaultLink = item.defaultLink || '';

          const isVn = isVietnamMatch(allText);
          const isMu = isMuMatch(allText);
          const isPlOrC1 = isPremierLeagueOrC1(league, title, isVn);
          const isMajor = isMajorLeague(league, homeTeam, awayTeam, title, isVn);

          let ts = 0;
          if (item.matchTime) {
            ts = new Date(item.matchTime).getTime();
          }

          const matchObj = {
            id: `gavang:${slug}`,
            slug,
            matchId: item.matchId || slug,
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
            score: '',
            blvs,
            defaultLink,
            poster: homeLogo || awayLogo,
            source: 'gavang',
          };

          matchObj.priorityScore = calculateMatchScore(matchObj);
          matches.push(matchObj);
        } catch (e) {}
      });
    } catch (htmlErr) {
      console.error('GaVang HTML scrape failed:', htmlErr.message);
    }
  }

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
      id: `gavang:${slug}`,
      slug,
      name: matchInfo.title,
      time: matchInfo.time,
      league: matchInfo.league,
      homeTeam: matchInfo.homeTeam,
      awayTeam: matchInfo.awayTeam,
      homeLogo: matchInfo.homeLogo,
      awayLogo: matchInfo.awayLogo,
      description: `🏆 Giải đấu: ${matchInfo.league}\n⏱️ Thời gian: ${matchInfo.time}\n⚽ Trận đấu: ${matchInfo.homeTeam} vs ${matchInfo.awayTeam}\n📺 Trực tiếp từ Gà Vàng TV với bình luận tiếng Việt.`,
      genres: [matchInfo.league, 'Trực Tiếp Bóng Đá', 'Gà Vàng TV'],
      type: 'tv',
      isHot: matchInfo.isHot,
      isVietnam: matchInfo.isVietnam,
      isLive: matchInfo.isLive,
    };
  }

  return {
    id: `gavang:${slug}`,
    slug,
    name: `Trận đấu ${slug.replace(/-/g, ' ')}`,
    description: 'Trực tiếp từ Gà Vàng TV',
    genres: ['Trực Tiếp Bóng Đá', 'Gà Vàng TV'],
    type: 'tv',
  };
}

async function getMatchStreams(slug) {
  const allMatches = await getLiveMatches();
  const match = allMatches.find((m) => m.slug === slug);
  const streams = [];
  const seenUrls = new Set();
  const baseUrl = getBaseUrl();

  if (match && Array.isArray(match.blvs) && match.blvs.length > 0) {
    match.blvs.forEach((blv) => {
      const blvLabel = blv.name.toUpperCase().includes('BLV') ? blv.name : `BLV ${blv.name}`;
      const m3u8Url = (blv.streamUrls || []).find((u) => u.includes('.m3u8')) || blv.streamUrls[0];

      if (m3u8Url && !seenUrls.has(m3u8Url)) {
        seenUrls.add(m3u8Url);
        streams.push({
          name: `Gà Vàng • ${blvLabel}`,
          title: `${blvLabel} - Trực Tiếp (Full HD)`,
          url: m3u8Url,
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
    });
  }

  // Fallback to default link if available
  if (match && match.defaultLink && !seenUrls.has(match.defaultLink)) {
    seenUrls.add(match.defaultLink);
    streams.push({
      name: 'Gà Vàng • Kênh Mặc Định',
      title: 'Trực Tiếp (Full HD)',
      url: match.defaultLink,
      headers: {
        'Referer': baseUrl,
        'User-Agent': MOBILE_UA,
        'Origin': baseUrl,
      },
    });
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
