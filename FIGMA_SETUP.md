# DoneFirst → Figma Setup

Your token: `<YOUR_FIGMA_API_KEY>`

## Option A: Claude Code (recommended — works on Windows)

```powershell
cd C:\Users\veerp\DoneFirst\donefirst
npx @anthropic-ai/claude-code
```

Then inside Claude Code:
```
/mcp add figma --url https://mcp.figma.com/mcp --env FIGMA_API_KEY=<YOUR_FIGMA_API_KEY>
```

Then paste prompts from `figma_generate_prompt.md`.

## Option B: Cursor

Add to `~/.cursor/mcp.json`:
```json
{
  "mcpServers": {
    "figma": {
      "url": "https://mcp.figma.com/mcp",
      "env": {
        "FIGMA_API_KEY": "<YOUR_FIGMA_API_KEY>"
      }
    }
  }
}
```

## Option C: VS Code + Continue

Add to `~/.continue/config.json`:
```json
{
  "experimental": {
    "mcpServers": {
      "figma": {
        "type": "sse",
        "url": "https://mcp.figma.com/mcp",
        "env": {
          "FIGMA_API_KEY": "<YOUR_FIGMA_API_KEY>"
        }
      }
    }
  }
}
```

## What to do after connecting

1. Run prompts from `figma_generate_prompt.md` — one screen at a time
2. The `use_figma` tool on the MCP server handles all creation
3. All existing prompts use your exact design system colors and specs

## Files created for you
- `figma_design_spec.md` — full design system + all 23 screen specs
- `figma_generate_prompt.md` — paste-ready prompts for each screen
- `figma_mcp_config.json` — config for Cursor/Windsurf/Zed/etc.
