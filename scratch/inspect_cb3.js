const fs = require('fs');
const html = fs.readFileSync('/tmp/gdrive_page.html', 'utf8');

const regex = /AF_initDataCallback\s*\(\s*\{[^}]*?data\s*:\s*([\s\S]*?)\s*,\s*sideChannel:/g;
let m;
const cbs = [];
while ((m = regex.exec(html)) !== null) {
  try {
    cbs.push(JSON.parse(m[1].trim()));
  } catch (e) {}
}

const cb3 = cbs[3];

// Let's inspect cb3
// Where are the items in cb3?
console.log('cb3 type:', Array.isArray(cb3) ? 'Array, len=' + cb3.length : typeof cb3);

function findItems(arr, depth = 0) {
  if (!Array.isArray(arr)) return;
  // If element is an array of length >= 10 and has [null, id] or folder mime
  for (const item of arr) {
    if (Array.isArray(item)) {
      // Check if item has ID like [null, "1bt..."]
      if (item[0] && Array.isArray(item[0]) && typeof item[0][1] === 'string' && item[0][1].length > 20) {
        const id = item[0][1];
        const mime = item[4] || '';
        // Find title
        // Let's print out the first item structure
        console.log('Item found! ID:', id, 'Mime:', mime);
        // Print item keys or interesting fields
        console.log('Full Item json:', JSON.stringify(item).substring(0, 400));
      } else {
        findItems(item, depth + 1);
      }
    }
  }
}

findItems(cb3);
