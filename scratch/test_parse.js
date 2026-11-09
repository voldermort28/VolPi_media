const fs = require('fs');

const html = fs.readFileSync('/tmp/gdrive_page.html', 'utf8');
const match = html.match(/_DRIVE_ivd['"]?\s*=\s*'([^']+)'/);

if (!match) {
  console.log('No _DRIVE_ivd match found!');
  process.exit(1);
}

console.log('Found match! Length:', match[1].length);

// Let's decode \xHH hex escapes properly:
function decodeHexEscapes(str) {
  return str.replace(/\\x([0-9A-Fa-f]{2})/g, (match, hex) => {
    return String.fromCharCode(parseInt(hex, 16));
  });
}

const unescaped = decodeHexEscapes(match[1]);
console.log('Unescaped snippet:', unescaped.substring(0, 300));

try {
  const parsed = JSON.parse(unescaped);
  console.log('Parsed successfully! Is array?', Array.isArray(parsed));
  if (Array.isArray(parsed) && Array.isArray(parsed[0])) {
    console.log('Total items in parsed[0]:', parsed[0].length);
    for (let i = 0; i < Math.min(5, parsed[0].length); i++) {
      const item = parsed[0][i];
      console.log(`Item ${i}: id=${item[0]}, name=${item[2]}, mime=${item[3]}`);
    }
  }
} catch (err) {
  console.error('Parse error:', err.message);
}
