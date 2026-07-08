// Try direct initialize with various auth methods
async function tryInit(authHeader, label) {
  const body = JSON.stringify({
    jsonrpc: '2.0', id: 1, method: 'initialize',
    params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'test', version: '1.0.0' } }
  });
  const headers = { 'Content-Type': 'application/json' };
  if (authHeader) headers['Authorization'] = authHeader;
  
  const res = await fetch('https://mcp.figma.com/mcp', { method: 'POST', headers, body });
  const text = await res.text();
  console.log(`${label}:`);
  console.log(`  Status: ${res.status}`);
  const www = res.headers.get('WWW-Authenticate');
  if (www) console.log(`  WWW-Auth: ${www.slice(0, 200)}`);
  console.log(`  Body: ${text.slice(0, 200)}\n`);
}

async function main() {
  // Try various auth methods
  await tryInit(null, 'No auth');
  await tryInit('Bearer <YOUR_FIGMA_API_KEY>', 'Bearer figd_');
  
  // Try X-Figma-Token as header (needs custom header, not Auth)
  const headers = {
    'Content-Type': 'application/json',
    'X-Figma-Token': '<YOUR_FIGMA_API_KEY>'
  };
  const body = JSON.stringify({
    jsonrpc: '2.0', id: 2, method: 'initialize',
    params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'test', version: '1.0.0' } }
  });
  const res = await fetch('https://mcp.figma.com/mcp', { method: 'POST', headers, body });
  const text = await res.text();
  console.log('X-Figma-Token:');
  console.log(`  Status: ${res.status}`);
  console.log(`  Body: ${text.slice(0, 300)}\n`);
  
  // Try same with proper accept header
  const res2 = await fetch('https://mcp.figma.com/mcp', {
    method: 'POST',
    headers: { ...headers, 'Accept': 'application/json, text/event-stream' },
    body
  });
  const text2 = await res2.text();
  console.log('X-Figma-Token + Accept:');
  console.log(`  Status: ${res2.status}`);
  const www = res2.headers.get('WWW-Authenticate');
  if (www) console.log(`  WWW-Auth: ${www.slice(0, 300)}`);
  console.log(`  Body: ${text2.slice(0, 300)}\n`);
  
  // Try figd_ token through OAuth (exchange token for OAuth access_token)
  console.log('=== Trying OAuth token exchange with figd_ ===\n');
  const tokenRes = await fetch('https://api.figma.com/v1/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
      subject_token: '<YOUR_FIGMA_API_KEY>',
      subject_token_type: 'urn:ietf:params:oauth:token-type:access_token',
      scope: 'mcp:connect',
    })
  });
  const tokenText = await tokenRes.text();
  console.log(`Token exchange: ${tokenRes.status}`);
  console.log(`Body: ${tokenText.slice(0, 300)}`);
}

main().catch(e => console.error(e.message));
