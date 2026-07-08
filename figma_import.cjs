const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { SseClientTransport } = require('@modelcontextprotocol/sdk/client/sse.js');
const fs = require('fs');
const path = require('path');

const FIGMA_TOKEN = process.env.FIGMA_API_KEY || '<YOUR_FIGMA_API_KEY>';
const SVGS_DIR = 'C:\\Users\\veerp\\DoneFirst\\donefirst\\figma_svgs';

async function main() {
  console.log('Connecting to Figma Remote MCP...');

  const transport = new SseClientTransport(
    new URL('https://mcp.figma.com/mcp'),
    {
      'X-Figma-Token': FIGMA_TOKEN,
      'Accept': 'text/event-stream',
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
    const { tools } = await client.listTools();
    console.log('Available tools:', tools.map(t => t.name).join(', '));

    // Try creating a file
    const result = await client.callTool({
      name: 'add_figma_file',
      arguments: {
        name: 'DoneFirst Design',
      },
    });
    console.log('Create result:', JSON.stringify(result));

    await transport.close();
  } catch (e) {
    console.error('Error:', e.message);
    console.error('Stack:', e.stack);
  }
}

main();
