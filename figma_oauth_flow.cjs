const http = require('http');
const https = require('https');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const SVGS_DIR = 'C:\\Users\\veerp\\DoneFirst\\donefirst\\figma_svgs';
const CALLBACK_PORT = 8090;
const CALLBACK_URL = `http://localhost:${CALLBACK_PORT}/callback`;
const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';

// Debug: try the well-known endpoints first
async function debugEndpoints() {
  console.log('=== Debug: Testing Figma API endpoints ===\n');
  
  const endpoints = [
    { name: 'MCP POST', url: 'https://mcp.figma.com/mcp', method: 'POST', headers: {'Content-Type': 'application/json'} },
    { name: 'MCP GET', url: 'https://mcp.figma.com/mcp', method: 'GET' },
    { name: 'OAuth auth server', url: 'https://api.figma.com/.well-known/oauth-authorization-server', method: 'GET' },
    { name: 'OAuth protected resource', url: 'https://mcp.figma.com/.well-known/oauth-protected-resource', method: 'GET' },
  ];
  
  for (const ep of endpoints) {
    try {
      const res = await fetch(ep.url, { method: ep.method, headers: ep.headers || {} });
      const text = await res.text();
      console.log(`${ep.name}:`);
      console.log(`  Status: ${res.status}`);
      console.log(`  WWW-Authenticate: ${res.headers.get('WWW-Authenticate') || '(none)'}`);
      console.log(`  Body: ${text.slice(0, 200)}\n`);
    } catch(e) {
      console.log(`${ep.name}: Error - ${e.message}\n`);
    }
  }
}

debugEndpoints().then(() => {
  console.log('=== Now attempting OAuth flow ===\n');
  
  // Now try the real OAuth flow
  const { StreamableHTTPClientTransport } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\streamableHttp.js');
  const { Client } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\index.js');
  const { UnauthorizedError } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\auth.js');

  class FigmaOAuthProvider {
    constructor() {
      this._tokens = null;
      this._clientInfo = null;
      this._codeVerifier = null;
      this._discoveryState = null;
      this._clientMetadata = {
        client_name: 'DoneFirst Import',
        redirect_uris: [CALLBACK_URL],
        grant_types: ['authorization_code', 'refresh_token'],
        response_types: ['code'],
        token_endpoint_auth_method: 'none',
      };
    }
    get redirectUrl() { return CALLBACK_URL; }
    get clientMetadata() { return this._clientMetadata; }
    clientInformation() { return this._clientInfo; }
    saveClientInformation(info) { console.log('saveClientInformation'); this._clientInfo = info; }
    tokens() { return this._tokens; }
    saveTokens(tokens) { console.log('Tokens saved:', !!tokens.access_token); this._tokens = tokens; }
    saveCodeVerifier(v) { this._codeVerifier = v; }
    codeVerifier() { return this._codeVerifier; }
    async state() { return Math.random().toString(36).slice(2); }
    saveDiscoveryState(s) { console.log('saveDiscoveryState'); this._discoveryState = s; }
    discoveryState() { return this._discoveryState; }
    validateResourceURL(url) { return url; }
    addClientAuthentication(h, p, tu, m) {}
    redirectToAuthorization(authorizationUrl) {
      console.log('\n=== AUTHORIZE IN BROWSER ===');
      console.log('Opening:', authorizationUrl.toString().slice(0, 100) + '...');
      exec(`start "" "${authorizationUrl.toString()}"`);
    }
  }

  function waitForCallback() {
    return new Promise((resolve) => {
      const server = http.createServer((req, res) => {
        console.log(`Callback received: ${req.url}`);
        const url = new URL(req.url, 'http://localhost');
        const code = url.searchParams.get('code');
        if (code) {
          res.writeHead(200, {'Content-Type':'text/html'});
          res.end('<html><body><h1>✅ Authorized!</h1><script>window.close()</script></body></html>');
          server.close();
          resolve(code);
        }
      });
      server.listen(CALLBACK_PORT);
    });
  }

  async function main() {
    console.log('\nStarting OAuth flow...\n');
    const authProvider = new FigmaOAuthProvider();
    const transport = new StreamableHTTPClientTransport(
      new URL('https://mcp.figma.com/mcp'), { authProvider }
    );
    const client = new Client({ name: 'fi', version: '1.0.0' });

    try {
      await client.connect(transport);
      console.log('Connected without OAuth?');
    } catch (e) {
      console.log(`Auth required: ${e.message}`);
    }

    console.log('\nWaiting for browser authorization...\n');
    const code = await waitForCallback();
    console.log(`Code received: ${code.slice(0, 10)}...`);

    await transport.finishAuth(code);
    console.log('Auth completed, reconnecting...\n');

    const client2 = new Client({ name: 'fi', version: '1.0.0' });
    const transport2 = new StreamableHTTPClientTransport(
      new URL('https://mcp.figma.com/mcp'), { authProvider }
    );
    await client2.connect(transport2);
    console.log('✅ Connected!\n');

    const { tools } = await client2.listTools();
    console.log('Tools:', tools.map(t => t.name).join(', '));

    // Import SVGs
    const svgFiles = fs.readdirSync(SVGS_DIR).filter(f => f.endsWith('.svg')).sort();
    console.log(`\nImporting ${svgFiles.length} screens...\n`);

    for (const file of svgFiles) {
      const svg = fs.readFileSync(path.join(SVGS_DIR, file), 'utf8');
      const name = file.replace('.svg', '');
      process.stdout.write(`${name}... `);
      try {
        await client2.callTool({
          name: 'use_figma', arguments: { operation: 'create_frame_from_svg', name, svg }
        });
        console.log('✅');
      } catch (e) {
        console.log(`❌ ${e.message.slice(0, 100)}`);
      }
    }
    console.log('\n🎉 Done!');
    await transport2.close();
  }

  main().catch(e => console.error('Error:', e.message, e.stack?.slice(0, 200)));
});
