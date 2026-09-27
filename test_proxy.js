const axios = require('axios');
const scraper = require('./scraper');

async function testHlsProxy() {
  console.log('Testing manifest retrieval...');
  const rawId = '3219';
  const server = '1';

  const streams = await scraper.getStreams(rawId);
  console.log('Raw streams:', streams);

  if (streams.length > 0) {
    const rawVlUrl = streams[0].url;
    console.log('Fetching raw .vl:', rawVlUrl);
    const res = await axios.get(rawVlUrl, {
      headers: {
        'Referer': 'https://play.vlstream.net/',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      },
    });

    const lines = res.data.split('\n');
    console.log('Playlist lines count:', lines.length);
    const firstSeg = lines.find(l => l.startsWith('http'));
    console.log('First segment URL:', firstSeg);

    if (firstSeg) {
      const segRes = await axios.get(firstSeg, {
        responseType: 'arraybuffer',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        },
      });
      const buf = Buffer.from(segRes.data);
      console.log('Raw segment size:', buf.length, 'First 10 bytes:', buf.slice(0, 10));

      const iendIdx = buf.indexOf('IEND');
      console.log('IEND index:', iendIdx);
      const tsBuf = iendIdx !== -1 ? buf.slice(iendIdx + 8) : buf;
      console.log('Cleaned TS size:', tsBuf.length, 'First byte:', tsBuf[0].toString(16), '(should be 47)');
      if (tsBuf[0] === 0x47) {
        console.log('🎉 SUCCESS: Clean MPEG-TS stream ready for Stremio Player!');
      }
    }
  }
}

testHlsProxy().catch(console.error);
