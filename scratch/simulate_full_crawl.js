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
        console.error('Decode error for', folderId, err.message);
      }
    }
    return files;
  } catch (e) {
    return [];
  }
}

function isVideoFile(name, mimeType) {
  if (mimeType && mimeType.startsWith('video/')) return true;
  const ext = (name || '').split('.').pop().toLowerCase();
  return ['mp4', 'mkv', 'avi', 'mov', 'webm', 'm4v', 'ts', 'flv'].includes(ext);
}

async function crawl(folderId, maxDepth = 3) {
  const queue = [{ id: folderId, name: 'Root', path: '', depth: 0 }];
  const visited = new Set();
  const allVideos = [];
  const allFolders = [];
  const directFolders = [];

  console.time('Crawl');
  while (queue.length > 0) {
    const batch = queue.splice(0, 10);
    const results = await Promise.all(
      batch.map(async (curr) => {
        if (visited.has(curr.id)) return null;
        visited.add(curr.id);
        const rawFiles = await fetchViaPublicWeb(curr.id);
        return { curr, rawFiles };
      })
    );

    for (const res of results) {
      if (!res) continue;
      const { curr, rawFiles } = res;
      const isRoot = curr.id === folderId;

      for (const f of rawFiles) {
        const isFolder = f.mimeType === 'application/vnd.google-apps.folder';
        const folderPath = curr.path ? `${curr.path} / ${f.name}` : (f.name || '');

        if (isFolder) {
          const folderObj = { id: f.id, name: f.name, folderPath, parentId: curr.id };
          if (isRoot) directFolders.push(folderObj);
          allFolders.push(folderObj);

          if (curr.depth < maxDepth && visited.size < 100) {
            queue.push({
              id: f.id,
              name: f.name,
              path: folderPath,
              depth: curr.depth + 1,
            });
          }
        } else if (isVideoFile(f.name, f.mimeType)) {
          allVideos.push({
            id: f.id,
            name: f.name,
            folderPath: curr.path,
            folderName: curr.name,
          });
        }
      }
    }
  }
  console.timeEnd('Crawl');

  console.log(`Visited folders: ${visited.size}`);
  console.log(`Direct folders at root: ${directFolders.length}`);
  console.log(`Total folders found: ${allFolders.length}`);
  console.log(`Total videos found: ${allVideos.length}`);
  console.log('\nSample videos:');
  allVideos.slice(0, 8).forEach((v) => console.log(`- [${v.folderPath || 'root'}] ${v.name}`));
}

crawl('1hq8czu5ojCuz6ONHpxepJsxvEW1q7YJ9');
