const { Client } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\index.js');
const { StreamableHttpClientTransport } = require('C:\\Users\\veerp\\node_modules\\@modelcontextprotocol\\sdk\\dist\\cjs\\client\\streamableHttp.js');

const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';

async function main() {
  console.log('Trying Streamable HTTP transport...');

  const transport = new StreamableHttpClientTransport(
    new URL('https://mcp.figma.com/mcp'),
    {
      headers: {
        'X-Figma-Token': FIGMA_TOKEN,
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

    const result = await client.listTools();
    console.log('Tools:', result.tools.map(t => t.name).join(', '));

    await transport.close();
  } catch (e) {
    console.error('Error:', e.message);
    if (e.cause) console.error('Cause:', e.cause);
  }
}

main();
