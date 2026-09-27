const axios = require('axios');
const cheerio = require('cheerio');

async function checkSports() {
  const res = await axios.get('https://xoilaczbn.tv/', {
    headers: { 'User-Agent': 'Mozilla/5.0' }
  });
  const $ = cheerio.load(res.data);

  $('a[href*="/truc-tiep/"]').each((i, el) => {
    const $link = $(el);
    const href = $link.attr('href') || '';
    if (!href.startsWith('/truc-tiep/') || href.includes('/link/')) return;

    const $card = $link.closest('.grid-match-item, .grid-match, div[class*="grid-match"]');
    const hasFootballClass = $card.find('.grid-match-item__footer-football').length > 0;
    const league = $card.find('.grid-match__league, .grid-match__league-name').first().text().trim();
    const slug = href.replace('/truc-tiep/', '').replace(/\/$/, '');
    const cardClass = $card.attr('class') || '';

    // Check if basketball/tennis/badminton/volleyball/esports
    const isOtherSport = cardClass.includes('basketball') ||
                         cardClass.includes('tennis') ||
                         cardClass.includes('badminton') ||
                         cardClass.includes('volleyball') ||
                         cardClass.includes('esports') ||
                         cardClass.includes('bkb') ||
                         cardClass.includes('other');

    console.log(`[${i}] ${slug} | League: ${league} | HasFootballFooter: ${hasFootballClass} | Class: ${cardClass}`);
  });
}
checkSports().catch(console.error);
