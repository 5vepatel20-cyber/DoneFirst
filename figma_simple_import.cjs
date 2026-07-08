const http = require('http');
const https = require('https');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';
const SVGS = 'C:\\Users\\veerp\\DoneFirst\\donefirst\\figma_svgs';
const PORT = 8090;
const REDIRECT_URI = `http://localhost:${PORT}/callback`;

// Step 1: Start callback server + open browser
function startServer() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      if (!req.url.startsWith('/callback')) return;
      const url = new URL(req.url, 'http://localhost');
      const code = url.searchParams.get('code');
      if (code) {
        res.writeHead(200, {'Content-Type':'text/html'});
        res.end('<h1>✅ Authorized!</h1><script>window.close()</script>');
        server.close();
        resolve(code);
      }
    });
    server.listen(PORT, () => {
      // Open authorization URL
      const authUrl = `https://www.figma.com/oauth/mcp?response_type=code&client_id=${TOKEN}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&scope=mcp:connect&state=import`;
      console.log('Opening browser for Figma authorization...');
      exec(`start "" "${authUrl}"`);
    });
  });
}

// Step 2: Exchange code for token
async function exchangeCode(code) {
  const res = await fetch('https://api.figma.com/v1/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: TOKEN,
      code: code,
      redirect_uri: REDIRECT_URI,
    })
  });
  const data = await res.json();
  console.log('Token exchange:', res.status, JSON.stringify(data).slice(0, 200));
  return data;
}

// Step 3: Use MCP with access token
async function mcpCall(accessToken, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request({
      hostname: 'mcp.figma.com', path: '/mcp', method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        'Content-Length': Buffer.byteLength(data),
      }
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, data: JSON.parse(d) }); }
        catch { resolve({ status: res.statusCode, data: d }); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function importAll(accessToken) {
  const svgFiles = fs.readdirSync(SVGS).filter(f => f.endsWith('.svg')).sort();
  console.log(`\nImporting ${svgFiles.length} screens...\n`);

  for (const file of svgFiles) {
    const svg = fs.readFileSync(path.join(SVGS, file), 'utf8');
    const name = file.replace('.svg', '');
    process.stdout.write(`${name}... `);

    const result = await mcpCall(accessToken, {
      jsonrpc: '2.0', id: Date.now(), method: 'use_figma',
      params: { operation: 'create_frame_from_svg', name, svg }
    });
    
    if (result.status === 200 && result.data?.result) {
      console.log('✅');
    } else {
      console.log(`❌ ${result.status} ${JSON.stringify(result.data).slice(0, 80)}`);
      // If use_figma doesn't exist, try initialize first
      if (result.data?.error?.code === -32601) {
        console.log('   Tool not found. Trying initialize...');
        const init = await mcpCall(accessToken, {
          jsonrpc: '2.0', id: Date.now(), method: 'initialize',
          params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'import', version: '1' } }
        });
        console.log(`   Initialize: ${init.status} ${JSON.stringify(init.data).slice(0, 100)}`);
        
        // List tools
        const tools = await mcpCall(accessToken, {
          jsonrpc: '2.0', id: Date.now(), method: 'tools/list', params: {}
        });
        console.log(`   Tools: ${JSON.stringify(tools.data).slice(0, 200)}`);
        return;
      }
    }
  }
  console.log('\n✅ All screens imported!');
}

async function main() {
  console.log('DoneFirst → Figma Import\n');

  // Check if token saved from previous run
  const tokenFile = path.join(__dirname, '.figma_token');
  let accessToken = null;
  
  if (fs.existsSync(tokenFile)) {
    accessToken = fs.readFileSync(tokenFile, 'utf8').trim();
    console.log('Using saved access token.\n');
  } else {
    console.log('Step 1: Authorize in your browser...\n');
    const code = await startServer();
    console.log(`\nAuthorization code received!\n`);

    console.log('Step 2: Exchanging for access token...\n');
    const tokens = await exchangeCode(code);
    accessToken = tokens.access_token;
    
    if (accessToken) {
      fs.writeFileSync(tokenFile, accessToken);
      console.log('Token saved for future use.\n');
    } else {
      console.log('Token exchange failed:', JSON.stringify(tokens));
      return;
    }
  }

  console.log('Step 3: Importing screens into Figma...\n');
  await importAll(accessToken);
}

main().catch(e => console.error('Error:', e.message));
