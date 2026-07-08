const { Client } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\index.js');
const { SSEClientTransport } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\sse.js');

const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';

async function main() {
  console.log('Connecting to Figma Remote MCP...');

  const transport = new SSEClientTransport(
    new URL('https://mcp.figma.com/mcp'),
    {
      requestInit: {
        headers: {
          'X-Figma-Token': FIGMA_TOKEN,
        },
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

    // List tools
    const result = await client.listTools();
    console.log('Tools:', result.tools.map(t => t.name + ': ' + (t.description || '').slice(0, 60)).join('\n'));

    await transport.close();
  } catch (e) {
    console.error('Error:', e.message);
    if (e.cause) console.error('Cause:', e.cause);
  }
}

main();
