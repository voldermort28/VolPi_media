const axios = require('axios');

async function fetchViaPublicWeb(folderId) {
  const url = `https://drive.google.com/drive/folders/${folderId}`;
  const res = await axios.get(url, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
    },
    timeout: 10000,
  });

  const html = res.data;
  const files = [];

  // Match _DRIVE_ivd data
  const match = html.match(/window\['_DRIVE_ivd'\]\s*=\s*'([^']+)'/);
  if (match && match[1]) {
    try {
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
              thumbnailLink: `https://drive.google.com/thumbnail?id=${id}&sz=w400`,
            });
          }
        }
      }
    } catch (err) {
      console.error('[GDriveService] Error decoding _DRIVE_ivd:', err.message);
    }
  }

  return files;
}

async function test() {
  console.time('fetchRoot');
  const rootFiles = await fetchViaPublicWeb('1hq8czu5ojCuz6ONHpxepJsxvEW1q7YJ9');
  console.timeEnd('fetchRoot');
  console.log(`Root files count: ${rootFiles.length}`);
  rootFiles.forEach((f) => console.log(`- [${f.mimeType === 'application/vnd.google-apps.folder' ? 'DIR' : 'FILE'}] ${f.name} (${f.id})`));

  // Now let's fetch the first subfolder: action fantasy (1btKxVnfWjabyeKo6Tp8VUYArndzj5ySc)
  console.time('fetchSub');
  const subFiles = await fetchViaPublicWeb('1btKxVnfWjabyeKo6Tp8VUYArndzj5ySc');
  console.timeEnd('fetchSub');
  console.log(`Subfolder items count: ${subFiles.length}`);
  subFiles.slice(0, 5).forEach((f) => console.log(`  - [${f.mimeType === 'application/vnd.google-apps.folder' ? 'DIR' : 'FILE'}] ${f.name}`));
}

test();
