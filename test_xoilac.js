const axios = require('axios');
const cheerio = require('cheerio');

async function testXoilac() {
  const res = await axios.get('https://xoilaczbn.tv/', {
    headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' }
  });
  const $ = cheerio.load(res.data);
  const matches = [];

  // Match containers
  $('a[href*="/truc-tiep/"]').each((_, el) => {
    const $link = $(el);
    const href = $link.attr('href') || '';
    if (!href.startsWith('/truc-tiep/') || href.includes('/link/')) return;

    const title = $link.attr('title') || '';
    const $container = $link.parent();
    const league = $container.find('.grid-match__league, .grid-match__league-name').first().text().trim();
    const date = $container.find('.grid-match__date, .time').first().text().trim();
    const homeTeam = $container.find('.grid-match__team--home-name, .home-team').first().text().trim();
    const awayTeam = $container.find('.grid-match__team--away-name, .away-team').first().text().trim();
    const homeLogo = $container.find('.team-logo-group-home-logo img').attr('src') || '';
    const awayLogo = $container.find('.team-logo-group-away-logo img').attr('src') || '';

    const matchSlug = href.replace('/truc-tiep/', '').replace(/\/$/, '');

    // Avoid duplicates
    if (matches.some(m => m.slug === matchSlug)) return;

    matches.push({
      id: `xoilac:${matchSlug}`,
      slug: matchSlug,
      title: title || `${homeTeam} vs ${awayTeam}`,
      homeTeam,
      awayTeam,
      homeLogo,
      awayLogo,
      league,
      date,
      href: `https://xoilaczbn.tv${href}`,
    });
  });

  console.log('Found matches:', matches.length);
  if (matches.length > 0) {
    console.log('Sample match:', JSON.stringify(matches[0], null, 2));

    // Test stream extraction
    const matchUrl = matches[0].href;
    console.log('Testing stream extraction from:', matchUrl);
    const matchPage = await axios.get(matchUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' }
    });

    const streamMatch = matchPage.data.match(/var\s+list_stream\s*=\s*(\[[\s\S]*?\]);/);
    if (streamMatch) {
      const listStream = JSON.parse(streamMatch[1]);
      console.log('Found stream channel groups:', listStream.length);

      for (let i = 0; i < listStream.length; i++) {
        const chanUrl = listStream[i][0];
        try {
          const embedRes = await axios.get(chanUrl, {
            headers: {
              'Referer': matchUrl,
              'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15',
            },
            timeout: 5000,
          });
          const m = embedRes.data.match(/var\s+urlStream\s*=\s*["']([^"']+)["']/);
          if (m) {
            let sUrl = m[1];
            if (sUrl.endsWith('.flv')) sUrl = sUrl.replace('.flv', '.m3u8');
            console.log(`Channel #${i + 1} stream URL:`, sUrl);
          }
        } catch (e) {
          console.error(`Error fetching channel ${i + 1}:`, e.message);
        }
      }
    }
  }
}

testXoilac().catch(console.error);
