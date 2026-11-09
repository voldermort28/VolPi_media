const axios = require('axios');

async function fetchViaPublicWeb(folderId) {
  const url = `https://drive.google.com/drive/folders/${folderId}`;
  try {
    const res = await axios.get(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
      },
      timeout: 8000,
    });

    const html = res.data;
    const files = [];

    const match = html.match(/window\['_DRIVE_ivd'\]\s*=\s*'([^']+)'/);
    if (match && match[1]) {
      const jsonCompat = match[1].replace(/\\x([0-9a-fA-F]{2})/g, '\\u00$1');
      const decoded = JSON.parse(`"${jsonCompat}"`);
      const parsed = JSON.parse(decoded);
      if (Array.isArray(parsed) && Array.isArray(parsed[0])) {
        for (const item of parsed[0]) {
          if (Array.isArray(item) && item[0]) {
            const id = item[0];
            const name = item[2] || 'Tập tin';
            const mimeType = item[3] || '';
            const size = item[13] || item[27] || item[10] || 0;
            files.push({
              id,
              name,
              mimeType,
              size: typeof size === 'number' ? size : 0,
            });
          }
        }
      }
    }
    return files;
  } catch (e) {
    return [];
  }
}

async function testParallel() {
  console.log('Fetching root folder...');
  const root = await fetchViaPublicWeb('1hq8czu5ojCuz6ONHpxepJsxvEW1q7YJ9');
  console.log(`Root has ${root.length} items`);
  const subfolders = root.filter((f) => f.mimeType === 'application/vnd.google-apps.folder');

  console.time('fetch 10 subfolders parallel');
  const results = await Promise.all(subfolders.map((sf) => fetchViaPublicWeb(sf.id)));
  console.timeEnd('fetch 10 subfolders parallel');

  let totalItems = 0;
  results.forEach((items, i) => {
    console.log(`- Subfolder "${subfolders[i].name}": ${items.length} items`);
    totalItems += items.length;
  });
  console.log(`Total items across 10 subfolders: ${totalItems}`);
}

testParallel();
