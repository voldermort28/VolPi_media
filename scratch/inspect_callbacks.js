const fs = require('fs');

const html = fs.readFileSync('/tmp/gdrive_page.html', 'utf8');

// Pattern: AF_initDataCallback({key: '...', hash: '...', data: [...]});
const callbacks = [];
const regex = /AF_initDataCallback\s*\(\s*\{[^}]*?data\s*:\s*([\s\S]*?)\s*,\s*sideChannel:/g;
let m;
while ((m = regex.exec(html)) !== null) {
  try {
    const rawData = m[1].trim();
    // Try to parse rawData
    const parsed = JSON.parse(rawData);
    callbacks.push(parsed);
  } catch (err) {
    console.log('Failed to parse callback block:', err.message);
  }
}

console.log(`Found ${callbacks.length} valid AF_initDataCallback blocks`);

function walk(obj, path = '', found = []) {
  if (!obj) return found;
  if (Array.isArray(obj)) {
    // Check if this array looks like an item: [ [null, "id"], ... "name", "mimeType" ]
    // or has [ "id", ... "name", "mimeType" ]
    // Let's inspect any element that has id or mimeType
    if (obj.length >= 4) {
      // Find possible id: string 20-40 chars [a-zA-Z0-9_-]
      let id = null;
      let name = null;
      let mimeType = null;
      let isFolder = false;

      // Check structure 1: obj[0] is array with [null, "id"]
      if (Array.isArray(obj[0]) && typeof obj[0][1] === 'string' && /^[a-zA-Z0-9_-]{25,}$/.test(obj[0][1])) {
        id = obj[0][1];
      } else if (typeof obj[0] === 'string' && /^[a-zA-Z0-9_-]{25,}$/.test(obj[0])) {
        id = obj[0];
      }

      // Check mimeType
      for (let i = 0; i < Math.min(obj.length, 15); i++) {
        if (typeof obj[i] === 'string') {
          if (obj[i].includes('application/vnd.google-apps.folder')) {
            mimeType = 'application/vnd.google-apps.folder';
            isFolder = true;
          } else if (obj[i].startsWith('video/') || obj[i].startsWith('audio/')) {
            mimeType = obj[i];
          }
        }
      }

      // If mimeType or name found
      if (id) {
        // Let's find name
        // Often name is in obj[4] or deep inside obj[21] or similar
        // Let's stringify and see
        // console.log('Potential item:', id, mimeType);
      }
    }

    for (let i = 0; i < obj.length; i++) {
      walk(obj[i], `${path}[${i}]`, found);
    }
  } else if (typeof obj === 'object') {
    for (const k of Object.keys(obj)) {
      walk(obj[k], `${path}.${k}`, found);
    }
  }
  return found;
}

callbacks.forEach((cb, idx) => {
  console.log(`--- Callback ${idx} ---`);
  // Let's search inside callback
  const jsonStr = JSON.stringify(cb);
  console.log(`Callback ${idx} string length: ${jsonStr.length}`);
  // Check if it has "action fantasy"
  if (jsonStr.includes('action fantasy')) {
    console.log(`Callback ${idx} CONTAINS "action fantasy"!`);
  }
});
