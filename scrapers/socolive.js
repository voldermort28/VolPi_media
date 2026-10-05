const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

const CANDIDATE_DOMAINS = [
  'https://webfifa55.live',
  'https://socolivevq.top',
  'https://socolive85.live',
  'https://socolivetvz.top',
];

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().socoliveBaseUrl || 'https://webfifa55.live';
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

/**
 * Phân tích thời gian thi đấu từ chuỗi của Socolive (thường là "HH:mm dd/MM" hoặc data-time)
 * Luôn quy đổi chính xác về múi giờ Việt Nam GMT+7.
 */
function parseSocoliveTime(timeStr, statusText = '') {
  if (!timeStr && !statusText) return { isLive: false, isFinished: false, ts: 0 };

  const combined = `${timeStr || ''} ${statusText || ''}`.toLowerCase();

  const isFinished = combined.includes('hết giờ') ||
                     combined.includes('kết thúc') ||
                     combined.includes('ft') ||
                     combined.includes('finished');

  const isLive = !isFinished && (
    combined.includes('đang diễn ra') ||
    combined.includes('trực tiếp') ||
    combined.includes('live') ||
    combined.includes('hiệp') ||
    combined.includes("'") ||
    combined.includes('phút') ||
    combined.includes('bù giờ') ||
    combined.includes('hoãn') ||
    combined.includes('delay') ||
    combined.includes('pen') ||
    combined.includes('11m')
  );

  const m = (timeStr || '').match(/(\d{1,2}):(\d{2})\s*[-/]?\s*(\d{1,2})[\./-](\d{1,2})/);
  if (!m) return { isLive, isFinished, ts: isLive ? Date.now() : 0 };

  const hour = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  const day = parseInt(m[3], 10);
  const month = parseInt(m[4], 10) - 1;

  const now = new Date();
  let year = now.getFullYear();
  if (now.getMonth() === 11 && month === 0) year += 1;

  // Socolive times are ALWAYS in Vietnam timezone (GMT+7).
  const mm = String(month + 1).padStart(2, '0');
  const dd = String(day).padStart(2, '0');
  const hh = String(hour).padStart(2, '0');
  const ii = String(min).padStart(2, '0');
  const isoStr = `${year}-${mm}-${dd}T${hh}:${ii}:00+07:00`;
  const ts = new Date(isoStr).getTime();

  return { isLive, isFinished, ts };
}

/**
 * Quy luật xếp loại đội bóng & giải đấu ưu tiên - ĐỒNG BỘ 100% VỚI XOILACZ
 */
function getTeamPriority(match) {
  const q = ` ${match.homeTeam} ${match.awayTeam} ${match.title} ${match.slug} ${match.league || ''} `.toLowerCase();

  // 1. Việt Nam Football (Level 1 - Supreme Highlight)
  const vnKeywords = [
    'việt nam', 'viet nam', 'vietnam', 'u23 việt nam', 'u22 việt nam', 'u19 việt nam', 'u21 việt nam',
    'đt việt nam', 'đội tuyển việt nam', 'đt nữ việt nam',
    'v-league', 'vleague', 'v.league', 'v league', 'cúp quốc gia', 'hạng nhất quốc gia',
    'nam định', 'hà nội fc', 'clb hà nội', 'công an hà nội', 'cahn',
    'thể công', 'viettel', 'hagl', 'hoàng anh gia lai', 'sông lam nghệ an', 'slna',
    'thanh hóa', 'bình định', 'hải phòng', 'bình dương', 'becamex', 'tp.hồ chí minh', 'tp hcm',
    'đà nẵng', 'quảng nam', 'hà tĩnh', 'hồng lĩnh hà tĩnh', 'khánh hòa', 'pvf'
  ];

  if (vnKeywords.some((k) => q.includes(k))) {
    return {
      level: 1,
      isFamous: true,
      isVietnam: true,
      tag: '⭐ [VIỆT NAM]',
      badgeText: '⭐ BÓNG ĐÁ VIỆT NAM ⭐',
      color: '#dc2626',
      badgeBg: '#7f1d1d',
      textColor: '#fde047',
    };
  }

  // 1b. Manchester United (Level 1 - Supreme User Favorite)
  if (
    q.includes('manchester united') ||
    q.includes('manchester utd') ||
    q.includes('man united') ||
    q.includes('man utd') ||
    q.includes('man u ') ||
    q.includes(' mu ') ||
    q.endsWith(' mu') ||
    q.startsWith('mu ')
  ) {
    return {
      level: 1,
      isFamous: true,
      isVietnam: false,
      tag: '⭐ [MU FAVORITE]',
      badgeText: '⭐ MANCHESTER UNITED ⭐',
      color: '#e11d48',
      badgeBg: '#991b1b',
      textColor: '#fde047',
    };
  }

  // Exclude non-top divisions, youth leagues, women's secondary leagues, and esports
  const leagueLower = (match.league || '').toLowerCase();
  const isLowerOrWomenLeague = leagueLower.includes('la liga 2') ||
                               leagueLower.includes('segunda') ||
                               leagueLower.includes('hypermotion') ||
                               leagueLower.includes('bundesliga 2') ||
                               leagueLower.includes('2. bundesliga') ||
                               leagueLower.includes('serie b') ||
                               leagueLower.includes('serie c') ||
                               leagueLower.includes('ligue 2') ||
                               leagueLower.includes('hạng 2') ||
                               leagueLower.includes('hạng 3') ||
                               leagueLower.includes('u17') ||
                               leagueLower.includes('u19') ||
                               leagueLower.includes('u21') ||
                               (leagueLower.includes('frauen') && !q.includes('việt nam')) ||
                               (leagueLower.includes('women') && !q.includes('việt nam')) ||
                               (leagueLower.includes('nữ') && !q.includes('việt nam'));

  if (isLowerOrWomenLeague) {
    return {
      level: 3,
      isFamous: false,
      isVietnam: false,
      tag: '',
      badgeText: '',
      color: '#334155',
      badgeBg: '#1e293b',
      textColor: '#38bdf8',
    };
  }

  // 2. Big Clubs (Level 2 - Tâm Điểm)
  const bigClubs = [
    { names: ['manchester city', 'man city', 'mancity'], label: 'Man City' },
    { names: ['arsenal'], label: 'Arsenal' },
    { names: ['liverpool'], label: 'Liverpool' },
    { names: ['chelsea'], label: 'Chelsea' },
    { names: ['tottenham', 'spurs'], label: 'Tottenham' },
    { names: ['aston villa'], label: 'Aston Villa' },
    { names: ['newcastle'], label: 'Newcastle' },
    { names: ['brighton'], label: 'Brighton' },
    { names: ['brentford'], label: 'Brentford' },
    { names: ['real madrid'], label: 'Real Madrid' },
    { names: ['barcelona', 'barca'], label: 'Barcelona' },
    { names: ['atletico madrid', 'atletico'], label: 'Atletico Madrid' },
    { names: ['bayern munich', 'bayern'], label: 'Bayern Munich' },
    { names: ['dortmund', 'bvb'], label: 'Dortmund' },
    { names: ['leverkusen', 'bayer leverkusen'], label: 'Leverkusen' },
    { names: ['paris saint-germain', 'psg', 'paris sg'], label: 'PSG' },
    { names: ['juventus', 'juve'], label: 'Juventus' },
    { names: ['inter milan'], label: 'Inter Milan' },
    { names: ['ac milan'], label: 'AC Milan' },
    { names: ['as roma', ' roma '], label: 'AS Roma' },
    { names: ['napoli'], label: 'Napoli' },
    { names: ['al nassr', 'al-nassr'], label: 'Al Nassr' },
    { names: ['al hilal', 'al-hilal'], label: 'Al Hilal' },
    { names: ['al ittihad', 'al-ittihad'], label: 'Al Ittihad' },
    { names: ['inter miami'], label: 'Inter Miami' },
    { names: ['benfica'], label: 'Benfica' },
    { names: ['porto'], label: 'Porto' },
    { names: ['sporting lisbon', 'sporting cp'], label: 'Sporting CP' },
  ];

  for (const team of bigClubs) {
    if (team.names.some((n) => q.includes(n))) {
      return {
        level: 2,
        isFamous: true,
        isVietnam: false,
        tag: '🔥 [TÂM ĐIỂM]',
        badgeText: `🔥 TÂM ĐIỂM: ${team.label.toUpperCase()} 🔥`,
        color: '#f59e0b',
        badgeBg: '#854d0e',
        textColor: '#fef08a',
      };
    }
  }

  // 2b. Major National Teams
  const nationalTeams = [
    { names: ['đt anh', 'tuyển anh', 'england'], label: 'ĐT Anh' },
    { names: ['đt pháp', 'tuyển pháp', 'france'], label: 'ĐT Pháp' },
    { names: ['đt đức', 'tuyển đức', 'germany'], label: 'ĐT Đức' },
    { names: ['đt ý', 'tuyển ý', 'italy'], label: 'ĐT Ý' },
    { names: ['đt tây ban nha', 'tuyển tây ban nha', 'spain'], label: 'ĐT Tây Ban Nha' },
    { names: ['đt bồ đào nha', 'tuyển bồ đào nha', 'portugal'], label: 'ĐT Bồ Đào Nha' },
    { names: ['đt hà lan', 'tuyển hà lan', 'netherlands'], label: 'ĐT Hà Lan' },
    { names: ['đt bỉ', 'tuyển bỉ', 'belgium'], label: 'ĐT Bỉ' },
    { names: ['đt argentina', 'tuyển argentina', 'argentina'], label: 'ĐT Argentina' },
    { names: ['đt brazil', 'tuyển brazil', 'brazil'], label: 'ĐT Brazil' },
    { names: ['đt nhật bản', 'tuyển nhật bản', 'japan'], label: 'ĐT Nhật Bản' },
    { names: ['đt hàn quốc', 'tuyển hàn quốc', 'korea'], label: 'ĐT Hàn Quốc' },
    { names: ['đt ai cập', 'tuyển ai cập', 'ai cập', 'egypt'], label: 'ĐT Ai Cập' },
    { names: ['đt ma rốc', 'tuyển ma rốc', 'ma rốc', 'morocco'], label: 'ĐT Ma Rốc' },
    { names: ['đt nam phi', 'nam phi', 'south africa'], label: 'ĐT Nam Phi' },
    { names: ['đt senegal', 'senegal'], label: 'ĐT Senegal' },
    { names: ['đt nigeria', 'nigeria'], label: 'ĐT Nigeria' },
    { names: ['đt mali', 'mali'], label: 'ĐT Mali' },
  ];

  const teamsOnly = ` ${match.homeTeam || ''} ${match.awayTeam || ''} `.toLowerCase();
  for (const team of nationalTeams) {
    if (team.names.some((n) => teamsOnly.includes(n) || (match.title && match.title.toLowerCase().includes(n)))) {
      return {
        level: 2,
        isFamous: true,
        isVietnam: false,
        tag: '🔥 [TÂM ĐIỂM]',
        badgeText: `🔥 TÂM ĐIỂM: ${team.label.toUpperCase()} 🔥`,
        color: '#f59e0b',
        badgeBg: '#854d0e',
        textColor: '#fef08a',
      };
    }
  }

  // 2c. Major Leagues (Level 2)
  const majorLeagues = [
    { names: ['premier league', 'ngoại hạng anh', 'epl', 'fa cup', 'cúp fa', 'carabao', 'efl cup', 'cúp liên đoàn anh'], label: 'Ngoại Hạng Anh' },
    { names: ['champions league', 'cúp c1', 'uefa champions', 'ucl'], label: 'UEFA Champions League' },
    { names: ['europa league', 'cúp c2', 'uefa europa', 'uel'], label: 'UEFA Europa League' },
    { names: ['conference league', 'cúp c3', 'uefa conference', 'uecl'], label: 'UEFA Conference League' },
    { names: ['siêu cúp châu âu', 'uefa super cup'], label: 'UEFA Super Cup' },
    { names: ['la liga', 'vđqg tây ban nha', 'copa del rey', 'cúp nhà vua', 'supercopa'], label: 'La Liga' },
    { names: ['serie a', 'vđqg ý', 'coppa italia', 'cúp ý', 'supercoppa italiana'], label: 'Serie A' },
    { names: ['bundesliga', 'vđqg đức', 'dfb-pokal', 'cúp qg đức', 'dfl-supercup'], label: 'Bundesliga' },
    { names: ['ligue 1', 'vđqg pháp', 'coupe de france', 'cúp qg pháp'], label: 'Ligue 1' },
    { names: ['world cup', 'vòng loại world cup', 'world cup qualifiers'], label: 'World Cup' },
    { names: ['uefa euro', 'vòng loại euro', 'euro 2024', 'euro 2028', 'cúp euro'], label: 'UEFA Euro' },
    { names: ['nations league', 'uefa nations'], label: 'UEFA Nations League' },
    { names: ['copa america'], label: 'Copa America' },
    { names: ['asian cup', 'afc asian cup', 'afc champions league', 'cúp c1 châu á', 'cúp c2 châu á', 'shopee cup', 'aff cup', 'asean cup', 'sea games', 'olympic'], label: 'Giải Châu Á / ĐNÁ' },
    { names: ['afcon', 'cúp châu phi', 'african cup', 'can 20', 'can 202'], label: 'Cúp Châu Phi (CAN)' },
    { names: ['concacaf', 'gold cup'], label: 'CONCACAF Gold Cup' },
    { names: ['giao hữu quốc tế', 'international friendly'], label: 'Giao Hữu Quốc Tế' },
    { names: ['saudi pro league', 'saudi league', 'vđqg ả rập xê út', 'roshn'], label: 'Saudi Pro League' },
    { names: ['mls', 'major league soccer', 'nhà nghề mỹ'], label: 'Major League Soccer' },
  ];

  for (const lg of majorLeagues) {
    if (lg.names.some((n) => q.includes(n))) {
      return {
        level: 2,
        isFamous: true,
        isVietnam: false,
        tag: '🔥 [TÂM ĐIỂM]',
        badgeText: `🔥 ${lg.label.toUpperCase()} 🔥`,
        color: '#0284c7',
        badgeBg: '#0369a1',
        textColor: '#e0f2fe',
      };
    }
  }

  // 3. Normal / Minor match (Level 3)
  return {
    level: 3,
    isFamous: false,
    isVietnam: false,
    tag: '',
    badgeText: '',
    color: '#334155',
    badgeBg: '#1e293b',
    textColor: '#38bdf8',
  };
}

async function getLiveMatches() {
  if (Date.now() - lastCacheTime < 60000 && cachedMatches.length > 0) {
    return cachedMatches;
  }

  try {
    const baseUrl = getBaseUrl();
    const res = await axios.get(baseUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
      },
      timeout: 10000,
      maxRedirects: 5,
    });

    if (res.request && res.request.res && res.request.res.responseUrl) {
      try {
        const u = new URL(res.request.res.responseUrl);
        resolvedBaseUrl = u.origin;
      } catch (e) {}
    }

    const currentBaseUrl = resolvedBaseUrl || baseUrl;
    const $ = cheerio.load(res.data);
    const matches = [];

    $('.match-item.match-data').each((_, el) => {
      const $card = $(el);
      const matchId = $card.attr('data-match-id') || '';
      const postId = $card.attr('data-post-id') || '';
      const sportId = ($card.attr('sport-id') || '').trim();
      const isLiveAttr = ($card.attr('is-live') || '').trim();
      const cardClass = ($card.attr('class') || '').toLowerCase();
      const isHot = cardClass.includes('hot-match');

      // STRICT FILTER: ONLY FOOTBALL MATCHES (sport-id: 1 is Football)
      if (sportId && sportId !== '1') return;

      const $link = $card.find('a.link-match').first();
      const href = $link.attr('href') || '';
      if (!href) return;

      const hrefLower = href.toLowerCase();
      if (hrefLower.includes('basketball') || hrefLower.includes('tennis') || hrefLower.includes('badminton') ||
          hrefLower.includes('volleyball') || hrefLower.includes('esports') || hrefLower.includes('dota')) {
        return;
      }

      const league = $card.find('.match-item__comp').first().text().trim() || 'Bóng đá';
      const time = $card.find('.match-item__time span').first().text().trim() || '';
      const homeTeam = $card.find('.name-home span').first().text().trim() || 'Đội nhà';
      const awayTeam = $card.find('.name-away span').first().text().trim() || 'Đội khách';

      let homeLogo = $card.find('.logo-home img').first().attr('src') || $card.find('.logo-home img').first().attr('data-src') || '';
      let awayLogo = $card.find('.logo-away img').first().attr('src') || $card.find('.logo-away img').first().attr('data-src') || '';

      if (homeLogo && homeLogo.startsWith('//')) homeLogo = 'https:' + homeLogo;
      else if (homeLogo && homeLogo.startsWith('/')) homeLogo = currentBaseUrl + homeLogo;
      if (awayLogo && awayLogo.startsWith('//')) awayLogo = 'https:' + awayLogo;
      else if (awayLogo && awayLogo.startsWith('/')) awayLogo = currentBaseUrl + awayLogo;

      // Extract match slug
      let slug = '';
      const slugMatch = href.match(/\/truc-tiep\/([^\/]+)/);
      if (slugMatch) {
        slug = slugMatch[1];
      } else if (matchId) {
        slug = matchId;
      }
      if (!slug || matches.some((m) => m.slug === slug)) return;

      // STRICT FILTER 2: Non-football keywords in league, teams, slug
      const allSportText = `${league} ${homeTeam} ${awayTeam} ${slug}`.toLowerCase();
      const nonFootballPatterns = [
        'esport', 'dota', 'blast slam', 'cs:go', 'cs2', 'counter-strike', 'league of legends',
        'crossfire', 'đột kích', 'valorant', 'pubg', 'arena of valor', 'tốc chiến', 'liên quân',
        'bóng rổ', 'basketball', 'nba', 'cba', 'vba',
        'tennis', 'quần vợt', 'atp', 'wta',
        'badminton', 'cầu lông', 'bwf',
        'volleyball', 'bóng chuyền', 'vnl',
        'bóng bàn', 'table tennis',
        'boxing', 'mma', 'ufc', 'one championship',
        'billiards', 'bi-a', 'snooker',
        'f1', 'formula', 'motogp', 'bóng chày', 'mlb', 'rugby'
      ];
      if (nonFootballPatterns.some((p) => allSportText.includes(p))) return;

      const statusText = $card.find('.status-match-data .status-text').first().text().trim() || $card.attr('data-status-text') || '';
      const timeParsed = parseSocoliveTime(time, statusText);

      const homeScore = $card.find('.home-score').first().text().trim();
      const awayScore = $card.find('.away-score').first().text().trim();
      const score = (homeScore && awayScore) ? `${homeScore} - ${awayScore}` : '';

      // Commentators on card
      const blvs = [];
      $card.find('.blv-item-scl a').each((_, blvEl) => {
        const $b = $(blvEl);
        const bHref = $b.attr('href') || '';
        const bName = $b.find('span').text().trim() || $b.text().trim();
        const bAvatar = $b.find('img').attr('src') || '';
        const m = bHref.match(/[?&]blv=([^&]+)/);
        const blvId = m ? m[1] : '';
        if (blvId || bName) {
          blvs.push({ blvId, name: bName, avatar: bAvatar });
        }
      });

      const matchObj = {
        id: `socolive:${slug}`,
        slug,
        matchId,
        postId,
        title: `${homeTeam} vs ${awayTeam}`,
        homeTeam,
        awayTeam,
        homeLogo,
        awayLogo,
        league,
        time,
        matchTimestamp: timeParsed.ts,
        isLive: isLiveAttr === '1' || cardClass.includes('live-match') || timeParsed.isLive,
        isFinished: cardClass.includes('finished') || timeParsed.isFinished,
        isHot,
        statusText,
        score,
        blvs,
      };

      matchObj.priority = getTeamPriority(matchObj);
      matchObj.isVietnam = matchObj.priority.isVietnam;
      matchObj.isFamous = matchObj.priority.isFamous;

      matches.push(matchObj);
    });

    // Helper functions for sorting
    const isFinishedMatch = (m) => {
      if (m.isFinished) return true;
      if (m.statusText) {
        const s = m.statusText.toLowerCase();
        if (s.includes('hết giờ') || s.includes('kết thúc') || s.includes('ft') || s.includes('finished')) return true;
      }
      if (m.matchTimestamp && !m.isLive) {
        const elapsedMin = (Date.now() - m.matchTimestamp) / (60 * 1000);
        if (elapsedMin > 115) return true;
      }
      return false;
    };

    const isOngoingMatch = (m) => {
      if (isFinishedMatch(m)) return false;
      if (m.isLive) return true;
      if (m.matchTimestamp) {
        const elapsedMin = (Date.now() - m.matchTimestamp) / (60 * 1000);
        if (elapsedMin >= 0 && elapsedMin <= 115) return true;
      }
      return false;
    };

    // Sort:
    // 1. Ongoing matches (trong 90') FIRST
    // 2. Finished matches LAST
    // 3. Level priority (MU & Việt Nam #1 -> Big Teams & Leagues #2 -> Others #3)
    // 4. Live matches (isLive)
    // 5. Chronological kickoff time
    matches.sort((a, b) => {
      const aOngoing = isOngoingMatch(a);
      const bOngoing = isOngoingMatch(b);
      if (aOngoing && !bOngoing) return -1;
      if (!aOngoing && bOngoing) return 1;

      const aFinished = isFinishedMatch(a);
      const bFinished = isFinishedMatch(b);
      if (!aFinished && bFinished) return -1;
      if (aFinished && !bFinished) return 1;

      const pA = a.priority ? a.priority.level : 3;
      const pB = b.priority ? b.priority.level : 3;
      if (pA !== pB) return pA - pB;

      if (a.isLive && !b.isLive) return -1;
      if (!a.isLive && b.isLive) return 1;

      if (a.matchTimestamp && b.matchTimestamp) {
        return a.matchTimestamp - b.matchTimestamp;
      }
      return 0;
    });

    cachedMatches = matches;
    lastCacheTime = Date.now();
    return matches;
  } catch (err) {
    console.error('Error fetching Socolive matches:', err.message);
    return cachedMatches;
  }
}

async function searchMatches(query) {
  const allMatches = await getLiveMatches();
  if (!query) return allMatches;

  const q = query.toLowerCase().trim();
  return allMatches.filter(
    (m) =>
      m.title.toLowerCase().includes(q) ||
      m.homeTeam.toLowerCase().includes(q) ||
      m.awayTeam.toLowerCase().includes(q) ||
      m.league.toLowerCase().includes(q)
  );
}

async function getMatchDetails(slug) {
  const allMatches = await getLiveMatches();
  const matchInfo = allMatches.find((m) => m.slug === slug);

  if (matchInfo) {
    return {
      id: `socolive:${slug}`,
      slug,
      name: matchInfo.title,
      time: matchInfo.time,
      league: matchInfo.league,
      homeTeam: matchInfo.homeTeam,
      awayTeam: matchInfo.awayTeam,
      homeLogo: matchInfo.homeLogo,
      awayLogo: matchInfo.awayLogo,
      priority: matchInfo.priority || getTeamPriority(matchInfo),
      description: `🏆 Giải đấu: ${matchInfo.league}\n⏱️ Thời gian: ${matchInfo.time}\n⚽ Trận đấu: ${matchInfo.homeTeam} vs ${matchInfo.awayTeam}\n📺 Trực tiếp từ Socolive TV với bình luận tiếng Việt.`,
      genres: [matchInfo.league, 'Trực Tiếp Bóng Đá', 'Socolive TV'],
      type: 'tv',
    };
  }

  return {
    id: `socolive:${slug}`,
    slug,
    name: `Trận đấu ${slug.replace(/-/g, ' ')}`,
    description: `Trực tiếp từ Socolive TV`,
    genres: ['Trực Tiếp Bóng Đá', 'Socolive TV'],
    type: 'tv',
  };
}

let livingRoomCache = [];
let lastLivingRoomFetch = 0;

/**
 * Lấy danh sách phòng livestream BLV đang hoạt động từ CDN API chính thức của Socolive
 */
async function getLivingRooms() {
  const now = Date.now();
  if (now - lastLivingRoomFetch < 15000 && livingRoomCache.length > 0) {
    return livingRoomCache;
  }
  try {
    const res = await axios.get('https://biz.vnres.co/api/live/livingRoom', {
      headers: {
        'User-Agent': USER_AGENT,
        'Accept': 'application/json',
      },
      timeout: 5000,
    });
    if (Array.isArray(res.data)) {
      livingRoomCache = res.data;
      lastLivingRoomFetch = now;
      return livingRoomCache;
    }
  } catch (e) {
    console.error('Error fetching Socolive livingRoom:', e.message);
  }
  return livingRoomCache;
}

/**
 * Chuẩn hóa URL stream của Socolive sang luồng HLS m3u8 có HTTPS hợp lệ:
 * CDN chính thức scstream.net -> pull.niues.live (có chứng chỉ SSL hợp lệ)
 * Đổi .flv -> .m3u8
 */
function formatSocoliveStreamUrl(rawUrl) {
  if (!rawUrl) return '';
  let streamUrl = rawUrl;
  streamUrl = streamUrl.replace(/^https?:\/\/pull[0-9]+\.scstream\.net\//i, 'https://pull.niues.live/');
  streamUrl = streamUrl.replace(/\.flv(?=([?#]|$))/i, '.m3u8');
  return streamUrl;
}

async function getMatchStreams(slug) {
  const streams = [];
  const baseUrl = resolvedBaseUrl || getBaseUrl();
  const matchUrl = `${baseUrl}/truc-tiep/${slug}/`;
  const host = process.env.BASE_HOST || 'https://stremio.laboon.vn';

  try {
    const pageRes = await axios.get(matchUrl, {
      headers: {
        'User-Agent': USER_AGENT,
        'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
      },
      timeout: 10000,
      maxRedirects: 5,
    });

    const finalMatchUrl = (pageRes.request && pageRes.request.res && pageRes.request.res.responseUrl)
      ? pageRes.request.res.responseUrl
      : matchUrl;

    try {
      resolvedBaseUrl = new URL(finalMatchUrl).origin;
    } catch (e) {}

    const html = pageRes.data;

    // 1. Parse window.streamData
    const streamDataMatch = html.match(/window\.streamData\s*=\s*(\{[\s\S]*?\});/);
    let streamData = null;
    if (streamDataMatch) {
      try {
        streamData = JSON.parse(streamDataMatch[1]);
      } catch (e) {}
    }

    const matchId = (streamData && streamData.matchId) || '';

    // 2. Parse BLV anchors from page
    const $ = cheerio.load(html);
    const anchors = [];

    // From streamData.anchors
    if (streamData && Array.isArray(streamData.anchors)) {
      streamData.anchors.forEach((a) => {
        if (a && (a.uid || a.roomID)) {
          anchors.push({
            uid: String(a.uid || a.roomID),
            roomID: String(a.roomID || a.uid || ''),
            name: a.nickName || a.name || a.streamer_name || 'BLV',
          });
        }
      });
    }

    // From HTML author/blv links
    $('.blv-item-scl a, .author-list a').each((_, el) => {
      const $a = $(el);
      const href = $a.attr('href') || '';
      const m = href.match(/[?&]blv=([^&]+)/);
      const name = $a.find('span').text().trim() || $a.text().trim();
      if (m && m[1]) {
        const uidStr = String(m[1]);
        if (!anchors.some((x) => x.uid === uidStr)) {
          anchors.push({ uid: uidStr, roomID: uidStr, name: name || 'BLV' });
        }
      }
    });

    // 3. Lấy danh sách luồng phát trực tiếp CDN Socolive đang hoạt động
    const livingRooms = await getLivingRooms();
    const lrMap = new Map();
    if (Array.isArray(livingRooms)) {
      livingRooms.forEach((item) => {
        if (item && item.id && item.stream) {
          lrMap.set(String(item.id), item.stream);
        }
      });
    }

    const seenUrls = new Set();

    // 4. Ưu tiên hàng đầu: Các luồng BLV ĐANG PHÁT TRỰC TIẾP (CDN HTTPS xịn, độ trễ cực thấp, không lỗi SSL)
    for (let i = 0; i < anchors.length; i++) {
      const anchor = anchors[i];
      const activeStream = lrMap.get(anchor.uid) || lrMap.get(anchor.roomID);

      if (activeStream) {
        const streamUrl = formatSocoliveStreamUrl(activeStream);
        if (!seenUrls.has(streamUrl)) {
          seenUrls.add(streamUrl);
          const label = anchor.name.toUpperCase().includes('BLV') ? anchor.name : `BLV ${anchor.name}`;
          streams.push({
            name: `Socolive • ${label}`,
            title: `${label} - Trực Tiếp (Full HD)`,
            url: streamUrl,
            headers: {
              'Referer': finalMatchUrl,
              'User-Agent': USER_AGENT,
              'Origin': baseUrl,
            },
            behaviorHints: {
              notWebReady: false,
              proxyHeaders: {
                request: {
                  'User-Agent': USER_AGENT,
                  'Referer': finalMatchUrl,
                },
              },
            },
          });
        }
      }
    }

    // 5. Luồng Dự Phòng (Qua Backend HTTPS Proxy để tránh lỗi SSL từ live.inplyr.com)
    for (let i = 0; i < anchors.length; i++) {
      const anchor = anchors[i];
      const hasActive = lrMap.has(anchor.uid) || lrMap.has(anchor.roomID);
      if (!hasActive) {
        const rawFallback = `http://live.inplyr.com/room/${anchor.uid}.m3u8`;
        const proxiedUrl = `${host}/api/iptv/stream-proxy?url=${encodeURIComponent(rawFallback)}&ref=${encodeURIComponent(finalMatchUrl)}`;
        if (!seenUrls.has(proxiedUrl)) {
          seenUrls.add(proxiedUrl);
          const label = anchor.name.toUpperCase().includes('BLV') ? anchor.name : `BLV ${anchor.name}`;
          streams.push({
            name: `Socolive • ${label} (Dự phòng)`,
            title: `${label} (Dự phòng)`,
            url: proxiedUrl,
            headers: {
              'Referer': finalMatchUrl,
              'User-Agent': USER_AGENT,
            },
            behaviorHints: {
              notWebReady: false,
            },
          });
        }
      }
    }

    // 6. Luồng Kênh Mặc Định (Qua Backend HTTPS Proxy)
    if (matchId) {
      const rawDefault = `http://live.inplyr.com/default/${matchId}.m3u8`;
      const proxiedDefault = `${host}/api/iptv/stream-proxy?url=${encodeURIComponent(rawDefault)}&ref=${encodeURIComponent(finalMatchUrl)}`;
      if (!seenUrls.has(proxiedDefault)) {
        seenUrls.add(proxiedDefault);
        streams.push({
          name: 'Socolive • Kênh Mặc Định (Dự phòng)',
          title: 'Kênh Mặc Định (Dự phòng)',
          url: proxiedDefault,
          headers: {
            'Referer': finalMatchUrl,
            'User-Agent': USER_AGENT,
          },
          behaviorHints: {
            notWebReady: false,
          },
        });
      }
    }

    // 7. Fallback: Parse các liên kết .m3u8 trực tiếp được nhúng trong trang (Bọc qua proxy nếu là inplyr)
    const m3u8Matches = html.matchAll(/["'](https?:\/\/[^"']+\.m3u8[^"']*)["']/gi);
    let fallbackIdx = 1;
    for (const m of m3u8Matches) {
      let foundUrl = m[1].replace(/\\\//g, '/');
      if (!foundUrl.includes('test') && !foundUrl.includes('banner')) {
        if (foundUrl.includes('inplyr.com')) {
          foundUrl = `${host}/api/iptv/stream-proxy?url=${encodeURIComponent(foundUrl.replace('https://', 'http://'))}&ref=${encodeURIComponent(finalMatchUrl)}`;
        }
        if (!seenUrls.has(foundUrl)) {
          seenUrls.add(foundUrl);
          streams.push({
            name: `Socolive • Kênh Dự Phòng #${fallbackIdx}`,
            title: `Kênh Dự Phòng #${fallbackIdx}`,
            url: foundUrl,
            headers: {
              'Referer': finalMatchUrl,
              'User-Agent': USER_AGENT,
            },
            behaviorHints: {
              notWebReady: false,
            },
          });
          fallbackIdx++;
        }
      }
    }

    return streams;
  } catch (err) {
    console.error(`Error fetching Socolive streams for ${slug}:`, err.message);
    return [];
  }
}

module.exports = {
  getBaseUrl,
  getLiveMatches,
  searchMatches,
  getMatchDetails,
  getMatchStreams,
  getTeamPriority,
  parseSocoliveTime,
  clearCache,
  USER_AGENT,
  MOBILE_UA,
};
