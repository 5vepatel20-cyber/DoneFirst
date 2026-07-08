const m = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\streamableHttp.js');
console.log('Streamable HTTP exports:', Object.keys(m));

// Also check if there's a lower-level approach
const http = require('https');
const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';

// Try a direct POST with initialize
async function main() {
  const body = JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'test', version: '1.0.0' },
    },
  });

  return new Promise((resolve, reject) => {
    const url = new URL('https://mcp.figma.com/mcp');
    const req = http.request({
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Figma-Token': FIGMA_TOKEN,
        'Accept': 'application/json, text/event-stream',
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        console.log('Status:', res.statusCode);
        console.log('Headers:', JSON.stringify(res.headers));
        console.log('Body:', data.slice(0, 500));
        resolve();
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

main().then(() => console.log('Done')).catch(e => console.error(e));
