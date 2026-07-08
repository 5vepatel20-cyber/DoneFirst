const { StreamableHTTPClientTransport } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\streamableHttp.js');
const { Client } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\index.js');
const { execSync } = require('child_process');

const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';

async function main() {
  // Try Streamable HTTP transport
  const transport = new StreamableHTTPClientTransport(
    new URL('https://mcp.figma.com/mcp'),
    {
      headers: {
        'Authorization': 'Bearer ' + FIGMA_TOKEN,
      },
    }
  );

  const client = new Client({
    name: 'opencode',
    version: '1.0.0',
  });

  try {
    await client.connect(transport);
    console.log('Connected!');
    const tools = await client.listTools();
    console.log('Tools:', tools.tools.map(t => t.name).join(', '));
    await transport.close();
  } catch (e) {
    console.error('Error:', e.message);
    if (e.cause) console.error('Cause:', e.cause);
    if (e.response) console.error('Response:', e.response.status);
  }
}

main();
