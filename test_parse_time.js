const axios = require('axios');
const cheerio = require('cheerio');

async function testParse() {
  const res = await axios.get('https://xoilaczbn.tv/', {
    headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' }
  });
  const $ = cheerio.load(res.data);
  const results = [];

  $('a[href*="/truc-tiep/"]').each((_, el) => {
    const $link = $(el);
    const href = $link.attr('href') || '';
    if (!href.startsWith('/truc-tiep/') || href.includes('/link/')) return;

    const $card = $link.closest('.grid-match-item, .grid-match, div[class*="grid-match"]');
    const title = $link.attr('title') || '';
    
    // Extract time / date
    let time = $card.find('.grid-match__date').text().trim() ||
               $card.find('.time, .t_time').attr('data-time') ||
               $card.find('.time, .t_time').text().trim();
    
    // Extract league
    const league = $card.find('.grid-match__league, .grid-match__league-name').first().text().trim();
    
    // Extract teams
    const homeTeam = $card.find('.grid-match__team--home-name, .team--home .team-name, .home-team').first().text().trim();
    const awayTeam = $card.find('.grid-match__team--away-name, .team--away .team-name, .away-team').first().text().trim();

    // Parse time from title if not in card: e.g. "Cagliari vs Lecce lúc 23:30 ngày 07/09/2026"
    if (!time && title) {
      const matchTime = title.match(/lúc\s+(\d{1,2}:\d{2})\s+ngày\s+(\d{1,2}\/\d{1,2})/i);
      if (matchTime) {
        time = `${matchTime[1]} - ${matchTime[2]}`;
      }
    }

    const slug = href.replace('/truc-tiep/', '').replace(/\/$/, '');
    if (results.some(r => r.slug === slug)) return;

    results.push({
      slug,
      title,
      homeTeam,
      awayTeam,
      league,
      time,
    });
  });

  console.log('Parsed matches count:', results.length);
  console.log('Sample parsed 5 matches:', results.slice(0, 5));
}

testParse().catch(console.error);
