const path = require('path');
const fs = require('fs');

const sdkRoot = 'C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk';
const pkg = JSON.parse(fs.readFileSync(path.join(sdkRoot, 'package.json'), 'utf8'));
console.log('Version:', pkg.version);
console.log('Main:', pkg.main);

// Check what dist exports
const distDir = path.join(sdkRoot, 'dist');
const files = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  fs.readdirSync(dir).forEach(f => {
    const fp = path.join(dir, f);
    if (fs.statSync(fp).isDirectory()) walk(fp);
    else files.push(fp);
  });
}
walk(distDir);
console.log('Dist files:', files.filter(f => f.endsWith('.js')).slice(0, 20));
