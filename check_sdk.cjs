const path = require('path');
const fs = require('fs');

// Find the SDK
const pkgPath = path.join(__dirname, 'node_modules', '@modelcontextprotocol', 'sdk', 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
console.log('Version:', pkg.version);
console.log('Main:', pkg.main);
console.log('Exports:', JSON.stringify(pkg.exports, null, 2));

// Try to find the main entry
const mainPath = path.join(__dirname, 'node_modules', '@modelcontextprotocol', 'sdk', pkg.main);
console.log('Main path:', mainPath, fs.existsSync(mainPath));

// Look for dist directory
const distDir = path.join(__dirname, 'node_modules', '@modelcontextprotocol', 'sdk', 'dist');
if (fs.existsSync(distDir)) {
  console.log('Dist contents:', fs.readdirSync(distDir));
}
