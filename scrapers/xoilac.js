const axios = require('axios');
const cheerio = require('cheerio');
const config = require('../config');

let resolvedBaseUrl = null;

function getBaseUrl() {
  if (resolvedBaseUrl) return resolvedBaseUrl;
  return config.getConfig().xoilacBaseUrl || 'https://xoilaczzw.cc';
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

function parseXoilacTime(timeStr, statusText = '') {
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

  const m = (timeStr || '').match(/(\d{1,2}):(\d{2})\s*[-/]\s*(\d{1,2})[\./-](\d{1,2})/);
  if (!m) return { isLive, isFinished, ts: isLive ? Date.now() : 0 };

  const hour = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  const day = parseInt(m[3], 10);
  const month = parseInt(m[4], 10) - 1;

  const now = new Date();
  let year = now.getFullYear();
  if (now.getMonth() === 11 && month === 0) year += 1;

  // IMPORTANT: Xoilac times are ALWAYS in Vietnam timezone (GMT+7).
  // Parse into UTC timestamp correctly regardless of server system timezone:
  const mm = String(month + 1).padStart(2, '0');
  const dd = String(day).padStart(2, '0');
  const hh = String(hour).padStart(2, '0');
  const ii = String(min).padStart(2, '0');
  const isoStr = `${year}-${mm}-${dd}T${hh}:${ii}:00+07:00`;
  const ts = new Date(isoStr).getTime();

  return { isLive, isFinished, ts };
}

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

  // 2a. Highlighted Big Teams & User Favorites (Level 2)
  const bigTeams = [
    { names: ['manchester city', 'man city', 'mancity', ' mc '], label: 'Man City' },
    { names: ['liverpool'], label: 'Liverpool' },
    { names: ['arsenal'], label: 'Arsenal' },
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

  for (const team of bigTeams) {
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

  // 2b. Major & Famous Leagues Worldwide (Level 2)
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
    { names: ['euro', 'vòng loại euro', 'uefa euro'], label: 'UEFA Euro' },
    { names: ['nations league', 'uefa nations'], label: 'UEFA Nations League' },
    { names: ['copa america'], label: 'Copa America' },
    { names: ['asian cup', 'afc asian cup', 'afc champions league', 'cúp c1 châu á', 'cúp c2 châu á', 'shopee cup', 'aff cup', 'asean cup', 'sea games', 'olympic'], label: 'Giải Châu Á / ĐNÁ' },
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

  // 3. Normal / Obscure / Minor league match (Level 3 - Khu vực 2)
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

    $('a[href*="/truc-tiep/"]').each((_, el) => {
      const $link = $(el);
      const href = $link.attr('href') || '';
      if (!href.startsWith('/truc-tiep/') || href.includes('/link/')) return;

      const $card = $link.closest('.grid-match-item, .grid-match, div[class*="grid-match"]');

      // STRICT FILTER: ONLY FOOTBALL MATCHES (Exclude Basketball, Tennis, Badminton, Volleyball, Esports...)
      const isFootball = $card.hasClass('match-football-item') ||
                         $card.find('.grid-match-item__footer-football').length > 0;

      const isOtherSport = $card.hasClass('match-basketball-item') ||
                           $card.hasClass('match-tennis-item') ||
                           $card.hasClass('match-badminton-item') ||
                           $card.hasClass('match-volleyball-item') ||
                           $card.hasClass('match-esports-item') ||
                           href.includes('basketball') ||
                           href.includes('tennis') ||
                           href.includes('badminton') ||
                           href.includes('volleyball') ||
                           href.includes('esports');

      if (!isFootball || isOtherSport) return;

      const title = $link.attr('title') || '';
      
      let time = $card.find('.grid-match__date').text().trim() ||
                 $card.find('.time, .t_time').attr('data-time') ||
                 $card.find('.time, .t_time').text().trim();
      
      const league = $card.find('.grid-match__league, .grid-match__league-name').first().text().trim() || 'Bóng đá';
      const homeTeam = $card.find('.grid-match__team--home-name, .team--home .team-name, .home-team').first().text().trim() || 'Đội nhà';
      const awayTeam = $card.find('.grid-match__team--away-name, .team--away .team-name, .away-team').first().text().trim() || 'Đội khách';
      let homeLogo = $card.find('.team-logo-group-home-logo img, .team--home img, .home-logo img').first().attr('src') ||
                     $card.find('.team-logo-group-home-logo img, .team--home img, .home-logo img').first().attr('data-src') || '';
      let awayLogo = $card.find('.team-logo-group-away-logo img, .team--away img, .away-logo img').first().attr('src') ||
                     $card.find('.team-logo-group-away-logo img, .team--away img, .away-logo img').first().attr('data-src') || '';

      if (homeLogo && homeLogo.startsWith('//')) homeLogo = 'https:' + homeLogo;
      else if (homeLogo && homeLogo.startsWith('/')) homeLogo = currentBaseUrl + homeLogo;
      if (awayLogo && awayLogo.startsWith('//')) awayLogo = 'https:' + awayLogo;
      else if (awayLogo && awayLogo.startsWith('/')) awayLogo = currentBaseUrl + awayLogo;

      if (!time && title) {
        const matchTime = title.match(/lúc\s+(\d{1,2}:\d{2})\s+ngày\s+(\d{1,2}\/\d{1,2})/i);
        if (matchTime) {
          time = `${matchTime[1]} - ${matchTime[2]}`;
        }
      }

      const statusText = $card.find('.grid-match__status, .match-status, .badge, .time-status, .live-badge').text().trim();
      const matchSlug = href.replace('/truc-tiep/', '').replace(/\/$/, '');
      if (!matchSlug || matches.some((m) => m.slug === matchSlug)) return;

      // STRICT FILTER 1: Non-football keywords in league, teams, slug
      const allSportText = `${league} ${homeTeam} ${awayTeam} ${matchSlug} ${title}`.toLowerCase();
      const nonFootballPatterns = [
        'esport', 'dota', 'blast slam', 'stake ranked', 'winline', 'fox legacy',
        'cs:go', 'cs2', 'counter-strike', 'league of legends', 'emea masters',
        'valorant', 'pubg', 'arena of valor', 'tốc chiến', 'liên quân', 'pro league',
        'bóng rổ', 'basketball', 'nba', 'cba', 'vba',
        'tennis', 'quần vợt', 'atp', 'wta',
        'badminton', 'cầu lông', 'bwf',
        'volleyball', 'bóng chuyền', 'vnl',
        'bóng bàn', 'table tennis', 'ittf',
        'boxing', 'mma', 'ufc', 'one championship',
        'billiards', 'bi-a', 'snooker', 'pool 9',
        'f1', 'formula', 'đua xe', 'motogp',
        'baseball', 'bóng chày', 'mlb',
        'rugby', 'bóng bầu dục', 'nfl'
      ];
      if (nonFootballPatterns.some((p) => allSportText.includes(p))) return;

      // Check date in slug (e.g. luc-1000-ngay-26-09-2026): drop stale matches from days ago
      const slugDateMatch = matchSlug.match(/ngay-(\d{1,2})-(\d{1,2})-(\d{4})/);
      if (slugDateMatch) {
        const sDay = parseInt(slugDateMatch[1], 10);
        const sMonth = parseInt(slugDateMatch[2], 10) - 1;
        const sYear = parseInt(slugDateMatch[3], 10);
        const slugDate = new Date(sYear, sMonth, sDay);
        const now = new Date();
        const diffDays = (now - slugDate) / (1000 * 60 * 60 * 24);
        if (diffDays > 1.5) return;
      }

      const timeParsed = parseXoilacTime(time, statusText);

      // STRICT FILTER 2: Expired / Ended match filtering (within 90-105m)
      if (timeParsed.isFinished) return;

      if (timeParsed.ts > 0) {
        const now = Date.now();
        const elapsedMin = (now - timeParsed.ts) / (60 * 1000);
        if (elapsedMin > 0) {
          // If match started > 105m ago (1h45m - ended 90 mins):
          // Drop non-live matches. If marked live (delays/penalties), allow up to 135m max.
          if (elapsedMin > (timeParsed.isLive ? 135 : 105)) {
            return;
          }
        }
      }

      const matchObj = {
        id: `xoilac:${matchSlug}`,
        slug: matchSlug,
        title: '',
        homeTeam,
        awayTeam,
        homeLogo,
        awayLogo,
        league,
        time: time || 'Đang diễn ra',
        href: `${currentBaseUrl}${href}`,
      };

      const priority = getTeamPriority(matchObj);
      matchObj.priority = priority;
      matchObj.isFamous = !!priority.isFamous;
      matchObj.isVietnam = !!priority.isVietnam;

      const fullTitle = `${homeTeam} vs ${awayTeam}`;
      const prefix = priority.tag ? `${priority.tag} ` : '';
      const timeStr = time ? `[${time}] ` : '';
      matchObj.title = `${prefix}${timeStr}${fullTitle} (${league})`;

      matchObj.isLive = timeParsed.isLive;
      matchObj.matchTimestamp = timeParsed.ts;

      matches.push(matchObj);
    });

    // Helper to identify matches currently ongoing within 90 mins
    const isOngoingMatch = (m) => {
      if (!m.matchTimestamp) return !!m.isLive;
      const elapsed = (Date.now() - m.matchTimestamp) / (60 * 1000);
      return elapsed >= -5 && elapsed <= (m.isLive ? 110 : 95);
    };

    const isFinishedMatch = (m) => {
      if (!m.matchTimestamp) return false;
      const elapsed = (Date.now() - m.matchTimestamp) / (60 * 1000);
      return elapsed > (m.isLive ? 115 : 100);
    };

    // Sort:
    // 1. Ongoing matches (trong 90') FIRST
    // 2. Finished matches LAST
    // 3. Level priority (MU #1 -> Big Teams #2 -> Others #3)
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
    console.error('Error fetching Xôi Lạc matches:', err.message);
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
      id: `xoilac:${slug}`,
      slug,
      name: matchInfo.title,
      time: matchInfo.time,
      league: matchInfo.league,
      homeTeam: matchInfo.homeTeam,
      awayTeam: matchInfo.awayTeam,
      homeLogo: matchInfo.homeLogo,
      awayLogo: matchInfo.awayLogo,
      priority: matchInfo.priority || getTeamPriority(matchInfo),
      description: `🏆 Giải đấu: ${matchInfo.league}\n⏱️ Thời gian: ${matchInfo.time}\n⚽ Trận đấu: ${matchInfo.homeTeam} vs ${matchInfo.awayTeam}\n📺 Trực tiếp từ Xôi Lạc TV với bình luận tiếng Việt.`,
      genres: [matchInfo.league, 'Trực Tiếp Bóng Đá', 'Xôi Lạc TV'],
      type: 'tv',
    };
  }

  return {
    id: `xoilac:${slug}`,
    slug,
    name: `Trận đấu ${slug.replace(/-/g, ' ')}`,
    description: `Trực tiếp từ Xôi Lạc TV`,
    genres: ['Trực Tiếp Bóng Đá', 'Xôi Lạc TV'],
    type: 'tv',
  };
}

async function getMatchStreams(slug) {
  const streams = [];
  const baseUrl = resolvedBaseUrl || getBaseUrl();
  const matchUrl = `${baseUrl}/truc-tiep/${slug}/`;

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

    const streamMatch = pageRes.data.match(/var\s+list_stream\s*=\s*(\[[\s\S]*?\]);/);
    if (!streamMatch) return [];

    const listStream = JSON.parse(streamMatch[1]);

    // Parse channel labels from page (e.g. .player-link with data-link)
    const $ = cheerio.load(pageRes.data);
    const channelLabels = {};
    $('.player-link').each((_, el) => {
      const idx = $(el).attr('data-link');
      const label = $(el).text().trim();
      if (idx !== undefined && label) {
        channelLabels[idx] = label;
      }
    });

    const seenUrls = new Set();

    for (let i = 0; i < listStream.length; i++) {
      const channelUrls = listStream[i];
      if (!channelUrls || channelUrls.length === 0) continue;

      const rawLabel = channelLabels[i];
      let displayLabel = `Kênh #${i + 1}`;
      if (rawLabel) {
        displayLabel = rawLabel.toUpperCase().includes('BLV') || rawLabel.toUpperCase().includes('KÊNH')
          ? rawLabel
          : `BLV ${rawLabel}`;
      }

      for (let j = 0; j < channelUrls.length; j++) {
        let chanEmbedUrl = channelUrls[j];
        if (!chanEmbedUrl || typeof chanEmbedUrl !== 'string') continue;
        if (chanEmbedUrl.startsWith('//')) {
          chanEmbedUrl = 'https:' + chanEmbedUrl;
        } else if (chanEmbedUrl.startsWith('/')) {
          chanEmbedUrl = (resolvedBaseUrl || baseUrl) + chanEmbedUrl;
        }

        try {
          const embedRes = await axios.get(chanEmbedUrl, {
            headers: {
              'Referer': finalMatchUrl,
              'User-Agent': MOBILE_UA,
            },
            timeout: 7000,
          });

          const m = embedRes.data.match(/var\s+urlStream\s*=\s*["']([^"']+)["']/i) ||
                    embedRes.data.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)["']/i);
          if (m) {
            let sUrl = m[1];
            sUrl = sUrl.replace(/\.flv(\?|$)/i, '.m3u8$1');

            if (!seenUrls.has(sUrl)) {
              seenUrls.add(sUrl);
              const backupTag = channelUrls.length > 1 && j > 0 ? ` (Dự phòng ${j})` : '';

              streams.push({
                name: 'Xôi Lạc TV',
                title: `${displayLabel}${backupTag} - Tiếng Việt (Full HD)`,
                url: sUrl,
                behaviorHints: {
                  notWebReady: false,
                  proxyHeaders: {
                    request: {
                      'User-Agent': MOBILE_UA,
                      'Referer': chanEmbedUrl,
                    },
                  },
                },
              });
              break; // Found working stream for this channel entry
            }
          }
        } catch (e) {
          // Continue trying next channel embed URL
        }
      }
    }
  } catch (err) {
    console.error(`Error fetching streams for ${slug}:`, err.message);
  }

  return streams;
}

module.exports = {
  getLiveMatches,
  searchMatches,
  getMatchDetails,
  getMatchStreams,
  getTeamPriority,
  getBaseUrl,
  clearCache,
  USER_AGENT,
};
