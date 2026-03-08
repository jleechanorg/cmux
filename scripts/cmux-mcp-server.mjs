import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import process from 'node:process';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import * as z from 'zod';

const execFileAsync = promisify(execFile);
const DEFAULT_HTTP_PORT = 8765;
const DEFAULT_HTTP_HOST = '127.0.0.1';
const VALID_ID_FORMATS = new Set(['refs', 'uuids', 'both']);

const HELP_TEXT = `cmux MCP server

Usage:
  node scripts/cmux-mcp-server.mjs [--transport stdio|http] [--port 8765] [--host 127.0.0.1]

Environment:
  CMUX_MCP_CMUX_BIN           Path to the cmux CLI binary (default: cmux)
  CMUX_MCP_SOCKET_PATH        Optional socket path passed through as --socket
  CMUX_MCP_SOCKET_PASSWORD    Optional socket password passed through as --socket-password
  CMUX_MCP_ID_FORMAT          Default id format: refs, uuids, or both
  CMUX_MCP_HTTP_HOST          HTTP bind host (default: 127.0.0.1)
  CMUX_MCP_HTTP_PORT          HTTP bind port (default: 8765)
`;

function envValue(name) {
  const value = process.env[name];
  if (!value) return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseIntEnv(name, fallback) {
  const raw = envValue(name);
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function loadConfig() {
  const idFormat = envValue('CMUX_MCP_ID_FORMAT');
  return {
    cmuxBin: envValue('CMUX_MCP_CMUX_BIN') ?? 'cmux',
    socketPath: envValue('CMUX_MCP_SOCKET_PATH'),
    socketPassword: envValue('CMUX_MCP_SOCKET_PASSWORD'),
    idFormat: VALID_ID_FORMATS.has(idFormat) ? idFormat : 'refs',
    httpHost: envValue('CMUX_MCP_HTTP_HOST') ?? DEFAULT_HTTP_HOST,
    httpPort: parseIntEnv('CMUX_MCP_HTTP_PORT', DEFAULT_HTTP_PORT),
  };
}

function compactArgs(values) {
  return values.filter((value) => value !== undefined && value !== null && value !== '');
}

function requireField(value, name) {
  if (value === undefined || value === null || value === '') {
    throw new Error(`Missing required field: ${name}`);
  }
  return value;
}

function summarizeOutput(result) {
  if (result.data !== null) {
    return JSON.stringify(result.data, null, 2);
  }
  if (result.stdout) {
    return result.stdout;
  }
  if (result.stderr) {
    return result.stderr;
  }
  return `${result.command} completed`;
}

function formatStructured(result, extra = {}) {
  return {
    ok: true,
    command: result.command,
    argv: result.argv,
    stdout: result.stdout,
    stderr: result.stderr,
    data: result.data,
    ...extra,
  };
}

function toolResult(result, extra = {}) {
  return {
    content: [{ type: 'text', text: summarizeOutput(result) }],
    structuredContent: formatStructured(result, extra),
  };
}

function parseCommandOutput(stdout) {
  if (!stdout) return null;
  try {
    return JSON.parse(stdout);
  } catch {
    return null;
  }
}

function buildCmuxInvoker(config = loadConfig()) {
  return async function runCmux(command, commandArgs = [], options = {}) {
    const json = options.json ?? true;
    const idFormat = options.idFormat ?? config.idFormat;
    const window = options.window;
    const argv = [];
    if (config.socketPath) {
      argv.push('--socket', config.socketPath);
    }
    if (config.socketPassword) {
      argv.push('--socket-password', config.socketPassword);
    }
    if (json) {
      argv.push('--json');
    }
    if (idFormat && VALID_ID_FORMATS.has(idFormat)) {
      argv.push('--id-format', idFormat);
    }
    if (window) {
      argv.push('--window', window);
    }
    argv.push(command, ...compactArgs(commandArgs));

    try {
      const { stdout, stderr } = await execFileAsync(config.cmuxBin, argv, {
        env: process.env,
        maxBuffer: 16 * 1024 * 1024,
      });
      const trimmedStdout = stdout.trim();
      const trimmedStderr = stderr.trim();
      return {
        ok: true,
        command,
        argv,
        stdout: trimmedStdout,
        stderr: trimmedStderr,
        data: json ? parseCommandOutput(trimmedStdout) : null,
      };
    } catch (error) {
      const stdout = typeof error.stdout === 'string' ? error.stdout.trim() : '';
      const stderr = typeof error.stderr === 'string' ? error.stderr.trim() : '';
      const suffix = [stderr, stdout].filter(Boolean).join('\n');
      throw new Error(
        `cmux ${argv.join(' ')} failed${suffix ? `\n${suffix}` : ''}`,
      );
    }
  };
}

function buildListCommand(input) {
  switch (input.target) {
    case 'windows':
      return { command: 'list-windows', args: [] };
    case 'workspaces':
      return { command: 'list-workspaces', args: [] };
    case 'panes':
      return {
        command: 'list-panes',
        args: compactArgs(['--workspace', input.workspace]),
      };
    case 'surfaces':
      return {
        command: 'list-panels',
        args: compactArgs(['--workspace', input.workspace]),
      };
    case 'pane_surfaces':
      return {
        command: 'list-pane-surfaces',
        args: compactArgs(['--workspace', input.workspace, '--pane', input.pane]),
      };
    default:
      throw new Error(`Unsupported list target: ${input.target}`);
  }
}

function buildControlCommand(input) {
  const common = {
    window: input.window,
    idFormat: input.idFormat,
  };

  switch (input.entity) {
    case 'window':
      switch (input.action) {
        case 'list':
          return { command: 'list-windows', args: [], options: common };
        case 'current':
          return { command: 'current-window', args: [], options: common };
        case 'create':
          return { command: 'new-window', args: [], options: { ...common, json: false } };
        case 'focus':
          return {
            command: 'focus-window',
            args: ['--window', requireField(input.windowTarget, 'windowTarget')],
            options: { ...common, json: false },
          };
        case 'close':
          return {
            command: 'close-window',
            args: ['--window', requireField(input.windowTarget, 'windowTarget')],
            options: { ...common, json: false },
          };
        default:
          break;
      }
      break;
    case 'workspace':
      switch (input.action) {
        case 'list':
          return { command: 'list-workspaces', args: [], options: common };
        case 'current':
          return { command: 'current-workspace', args: [], options: common };
        case 'create':
          return {
            command: 'new-workspace',
            args: compactArgs(['--cwd', input.cwd, '--command', input.commandText]),
            options: { ...common, json: false },
          };
        case 'select':
          return {
            command: 'select-workspace',
            args: ['--workspace', requireField(input.workspace, 'workspace')],
            options: common,
          };
        case 'close':
          return {
            command: 'close-workspace',
            args: ['--workspace', requireField(input.workspace, 'workspace')],
            options: common,
          };
        case 'rename':
          return {
            command: 'rename-workspace',
            args: ['--workspace', requireField(input.workspace, 'workspace'), '--', requireField(input.title, 'title')],
            options: common,
          };
        case 'move':
          return {
            command: 'move-workspace-to-window',
            args: [
              '--workspace',
              requireField(input.workspace, 'workspace'),
              '--window',
              requireField(input.targetWindow, 'targetWindow'),
            ],
            options: common,
          };
        case 'reorder':
          return {
            command: 'reorder-workspace',
            args: compactArgs([
              '--workspace',
              requireField(input.workspace, 'workspace'),
              '--before',
              input.before,
              '--after',
              input.after,
            ]),
            options: common,
          };
        case 'next':
          return { command: 'next-window', args: [], options: common };
        case 'previous':
          return { command: 'previous-window', args: [], options: common };
        case 'last':
          return { command: 'last-window', args: [], options: common };
        default:
          break;
      }
      break;
    case 'pane':
      switch (input.action) {
        case 'list':
          return {
            command: 'list-panes',
            args: compactArgs(['--workspace', input.workspace]),
            options: common,
          };
        case 'focus':
          return {
            command: 'focus-pane',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--pane',
              requireField(input.pane, 'pane'),
            ]),
            options: common,
          };
        case 'create':
          return {
            command: 'new-pane',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--type',
              input.surfaceType,
              '--direction',
              input.direction ?? 'right',
              '--url',
              input.url,
            ]),
            options: common,
          };
        default:
          break;
      }
      break;
    case 'surface':
      switch (input.action) {
        case 'list':
          return {
            command: 'list-panels',
            args: compactArgs(['--workspace', input.workspace]),
            options: common,
          };
        case 'create':
          return {
            command: 'new-surface',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--pane',
              input.pane,
              '--type',
              input.surfaceType,
              '--url',
              input.url,
            ]),
            options: common,
          };
        case 'split':
          return {
            command: 'new-split',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--surface',
              requireField(input.surface, 'surface'),
              requireField(input.direction, 'direction'),
            ]),
            options: common,
          };
        case 'focus':
          return {
            command: 'focus-panel',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--panel',
              requireField(input.surface, 'surface'),
            ]),
            options: common,
          };
        case 'close':
          return {
            command: 'close-surface',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--surface',
              requireField(input.surface, 'surface'),
            ]),
            options: common,
          };
        case 'move':
          return {
            command: 'move-surface',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--surface',
              requireField(input.surface, 'surface'),
              '--pane',
              input.targetPane,
              '--window',
              input.targetWindow,
              '--after',
              input.after,
              '--before',
              input.before,
              '--focus',
              typeof input.focus === 'boolean' ? String(input.focus) : undefined,
            ]),
            options: common,
          };
        case 'reorder':
          return {
            command: 'reorder-surface',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--surface',
              requireField(input.surface, 'surface'),
              '--before',
              input.before,
              '--after',
              input.after,
            ]),
            options: common,
          };
        case 'health':
          return {
            command: 'surface-health',
            args: compactArgs(['--workspace', input.workspace]),
            options: common,
          };
        case 'trigger_flash':
          return {
            command: 'trigger-flash',
            args: compactArgs([
              '--workspace',
              input.workspace,
              '--surface',
              requireField(input.surface, 'surface'),
            ]),
            options: common,
          };
        default:
          break;
      }
      break;
    default:
      break;
  }

  throw new Error(`Unsupported ${input.entity} action: ${input.action}`);
}

function buildTerminalCommand(input) {
  const options = {
    window: input.window,
    idFormat: input.idFormat,
  };

  switch (input.action) {
    case 'read':
      return {
        command: 'read-screen',
        args: compactArgs([
          '--workspace',
          input.workspace,
          '--surface',
          input.surface,
          '--lines',
          input.lines ? String(input.lines) : undefined,
          input.scrollback ? '--scrollback' : undefined,
        ]),
        options,
      };
    case 'send_text':
      return {
        command: 'send',
        args: compactArgs([
          '--workspace',
          input.workspace,
          '--surface',
          input.surface,
          '--',
          requireField(input.text, 'text'),
        ]),
        options,
      };
    case 'send_key':
      return {
        command: 'send-key',
        args: compactArgs([
          '--workspace',
          input.workspace,
          '--surface',
          input.surface,
          '--',
          requireField(input.key, 'key'),
        ]),
        options,
      };
    case 'clear_history':
      return {
        command: 'clear-history',
        args: compactArgs(['--workspace', input.workspace, '--surface', input.surface]),
        options,
      };
    default:
      throw new Error(`Unsupported terminal action: ${input.action}`);
  }
}

function buildBrowserCommand(input) {
  const options = {
    window: input.window,
    idFormat: input.idFormat,
  };
  const surface = input.surface;

  switch (input.action) {
    case 'open':
      return {
        command: 'browser',
        args: compactArgs([
          'open',
          '--workspace',
          input.workspace,
          '--surface',
          surface,
          requireField(input.url, 'url'),
        ]),
        options,
      };
    case 'navigate':
      return {
        command: 'browser',
        args: ['--surface', requireField(surface, 'surface'), 'navigate', requireField(input.url, 'url')],
        options,
      };
    case 'back':
    case 'forward':
    case 'reload':
    case 'get-url':
      return {
        command: 'browser',
        args: ['--surface', requireField(surface, 'surface'), input.action],
        options,
      };
    case 'snapshot':
      return {
        command: 'browser',
        args: compactArgs([
          '--surface',
          requireField(surface, 'surface'),
          'snapshot',
          '--selector',
          input.selector,
        ]),
        options,
      };
    case 'click':
      return {
        command: 'browser',
        args: [
          '--surface',
          requireField(surface, 'surface'),
          'click',
          '--selector',
          requireField(input.selector, 'selector'),
        ],
        options,
      };
    case 'fill':
    case 'type':
      return {
        command: 'browser',
        args: [
          '--surface',
          requireField(surface, 'surface'),
          input.action,
          '--selector',
          requireField(input.selector, 'selector'),
          '--text',
          requireField(input.text, 'text'),
        ],
        options,
      };
    case 'press':
      return {
        command: 'browser',
        args: [
          '--surface',
          requireField(surface, 'surface'),
          'press',
          '--key',
          requireField(input.key, 'key'),
        ],
        options,
      };
    case 'wait':
      return {
        command: 'browser',
        args: compactArgs([
          '--surface',
          requireField(surface, 'surface'),
          'wait',
          '--selector',
          input.selector,
          '--text',
          input.text,
          '--timeout-ms',
          input.timeoutMs ? String(input.timeoutMs) : undefined,
        ]),
        options,
      };
    default:
      throw new Error(`Unsupported browser action: ${input.action}`);
  }
}

function registerTools(server, runCmux) {
  server.registerTool(
    'cmux_identify',
    {
      description: 'Return the focused cmux window/workspace/pane/surface and optional caller resolution.',
      inputSchema: z.object({
        workspace: z.string().optional().describe('Optional caller workspace handle such as workspace:2'),
        surface: z.string().optional().describe('Optional caller surface handle such as surface:7'),
        window: z.string().optional().describe('Optional window override such as window:1'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const result = await runCmux(
        'identify',
        compactArgs(['--workspace', input.workspace, '--surface', input.surface]),
        { window: input.window, idFormat: input.idFormat },
      );
      return toolResult(result);
    },
  );

  server.registerTool(
    'cmux_tree',
    {
      description: 'Return the current cmux topology tree for discovery and routing.',
      inputSchema: z.object({
        window: z.string().optional().describe('Optional window handle'),
        workspace: z.string().optional().describe('Optional workspace handle'),
        surface: z.string().optional().describe('Optional caller surface handle'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const result = await runCmux(
        'tree',
        compactArgs(['--workspace', input.workspace, '--surface', input.surface]),
        { window: input.window, idFormat: input.idFormat },
      );
      return toolResult(result);
    },
  );

  server.registerTool(
    'cmux_list',
    {
      description: 'List windows, workspaces, panes, surfaces, or surfaces in a pane.',
      inputSchema: z.object({
        target: z.enum(['windows', 'workspaces', 'panes', 'surfaces', 'pane_surfaces']),
        window: z.string().optional().describe('Optional window handle'),
        workspace: z.string().optional().describe('Optional workspace handle'),
        pane: z.string().optional().describe('Optional pane handle'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const { command, args } = buildListCommand(input);
      const result = await runCmux(command, args, {
        window: input.window,
        idFormat: input.idFormat,
      });
      return toolResult(result, { target: input.target });
    },
  );

  server.registerTool(
    'cmux_control',
    {
      description: 'Create, focus, rename, move, reorder, split, or close cmux windows/workspaces/panes/surfaces.',
      inputSchema: z.object({
        entity: z.enum(['window', 'workspace', 'pane', 'surface']),
        action: z.enum([
          'list',
          'current',
          'create',
          'focus',
          'select',
          'close',
          'rename',
          'move',
          'reorder',
          'split',
          'health',
          'next',
          'previous',
          'last',
          'trigger_flash',
        ]),
        window: z.string().optional().describe('Optional window override'),
        windowTarget: z.string().optional().describe('Target window handle for window focus/close'),
        workspace: z.string().optional().describe('Target workspace handle'),
        pane: z.string().optional().describe('Target pane handle'),
        surface: z.string().optional().describe('Target surface handle'),
        targetWindow: z.string().optional().describe('Destination window for workspace or surface moves'),
        targetPane: z.string().optional().describe('Destination pane for surface moves'),
        before: z.string().optional().describe('Place target before this workspace or surface'),
        after: z.string().optional().describe('Place target after this workspace or surface'),
        title: z.string().optional().describe('New workspace title'),
        cwd: z.string().optional().describe('Working directory for new workspace creation'),
        commandText: z.string().optional().describe('Command to send after creating a workspace'),
        surfaceType: z.enum(['terminal', 'browser']).optional().describe('Surface type for pane/surface creation'),
        direction: z.enum(['left', 'right', 'up', 'down']).optional().describe('Split direction'),
        url: z.string().optional().describe('URL for browser pane/surface creation'),
        focus: z.boolean().optional().describe('Whether a move should focus the destination'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const { command, args, options } = buildControlCommand(input);
      const result = await runCmux(command, args, options);
      return toolResult(result, {
        entity: input.entity,
        action: input.action,
      });
    },
  );

  server.registerTool(
    'cmux_terminal',
    {
      description: 'Read terminal text, send text, send keys, or clear history for a terminal surface.',
      inputSchema: z.object({
        action: z.enum(['read', 'send_text', 'send_key', 'clear_history']),
        window: z.string().optional().describe('Optional window override'),
        workspace: z.string().optional().describe('Optional workspace handle'),
        surface: z.string().optional().describe('Optional surface handle'),
        lines: z.number().int().positive().optional().describe('Number of lines to read'),
        scrollback: z.boolean().optional().describe('Include scrollback when reading'),
        text: z.string().optional().describe('Text to send to the terminal'),
        key: z.string().optional().describe('Key to send, for example Enter or Escape'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const { command, args, options } = buildTerminalCommand(input);
      const result = await runCmux(command, args, options);
      return toolResult(result, { action: input.action });
    },
  );

  server.registerTool(
    'cmux_browser',
    {
      description: 'Run common browser actions against a browser-backed cmux surface.',
      inputSchema: z.object({
        action: z.enum([
          'open',
          'navigate',
          'back',
          'forward',
          'reload',
          'get-url',
          'snapshot',
          'click',
          'fill',
          'type',
          'press',
          'wait',
        ]),
        window: z.string().optional().describe('Optional window override'),
        workspace: z.string().optional().describe('Workspace handle for browser open'),
        surface: z.string().optional().describe('Browser surface handle'),
        selector: z.string().optional().describe('CSS selector or text selector depending on action'),
        text: z.string().optional().describe('Text for fill/type or wait content'),
        key: z.string().optional().describe('Key name for press'),
        script: z.string().optional().describe('Reserved for future browser eval support'),
        timeoutMs: z.number().int().positive().optional().describe('Optional timeout in milliseconds'),
        url: z.string().optional().describe('URL for open/navigate'),
        value: z.string().optional().describe('Additional positional value used by some browser subcommands'),
        idFormat: z.enum(['refs', 'uuids', 'both']).optional(),
      }),
    },
    async (input) => {
      const { command, args, options } = buildBrowserCommand(input);
      const result = await runCmux(command, args, options);
      return toolResult(result, { action: input.action });
    },
  );
}

export function buildServer(config = loadConfig()) {
  const runCmux = buildCmuxInvoker(config);
  const server = new McpServer(
    {
      name: 'cmux-mcp',
      version: '0.1.0',
    },
    {
      capabilities: { logging: {} },
    },
  );
  registerTools(server, runCmux);
  return server;
}

export async function runStdioServer(config = loadConfig()) {
  const server = buildServer(config);
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

export async function runHttpServer(config = loadConfig()) {
  const app = createMcpExpressApp();
  const transports = new Map();

  app.all('/mcp', async (req, res) => {
    try {
      const sessionIdHeader = req.headers['mcp-session-id'];
      const sessionId = Array.isArray(sessionIdHeader) ? sessionIdHeader[0] : sessionIdHeader;
      let transport = sessionId ? transports.get(sessionId) : undefined;

      if (!transport) {
        if (req.method !== 'POST' || !isInitializeRequest(req.body)) {
          res.status(400).json({
            jsonrpc: '2.0',
            error: { code: -32000, message: 'Expected an initialize POST to /mcp' },
            id: null,
          });
          return;
        }

        transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => randomUUID(),
          onsessioninitialized: (newSessionId) => {
            transports.set(newSessionId, transport);
          },
        });

        transport.onclose = () => {
          if (transport.sessionId) {
            transports.delete(transport.sessionId);
          }
        };

        const server = buildServer(config);
        await server.connect(transport);
      }

      await transport.handleRequest(req, res, req.body);
    } catch (error) {
      console.error('cmux-mcp http request failed:', error);
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: '2.0',
          error: { code: -32603, message: 'Internal server error' },
          id: null,
        });
      }
    }
  });

  const httpServer = createServer(app);
  await new Promise((resolve, reject) => {
    httpServer.once('error', reject);
    httpServer.listen(config.httpPort, config.httpHost, resolve);
  });

  console.error(`cmux-mcp listening on http://${config.httpHost}:${config.httpPort}/mcp`);
  return httpServer;
}

function parseCliArgs(argv) {
  const parsed = {
    transport: 'stdio',
    host: undefined,
    port: undefined,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
      continue;
    }
    if (arg === '--transport') {
      parsed.transport = argv[index + 1] ?? parsed.transport;
      index += 1;
      continue;
    }
    if (arg === '--host') {
      parsed.host = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === '--port') {
      const value = argv[index + 1];
      parsed.port = value ? Number.parseInt(value, 10) : undefined;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return parsed;
}

export async function main(argv = process.argv.slice(2)) {
  const parsed = parseCliArgs(argv);
  if (parsed.help) {
    process.stdout.write(HELP_TEXT);
    return;
  }

  const config = loadConfig();
  if (parsed.host) {
    config.httpHost = parsed.host;
  }
  if (Number.isFinite(parsed.port)) {
    config.httpPort = parsed.port;
  }

  if (parsed.transport === 'http') {
    await runHttpServer(config);
    return;
  }
  if (parsed.transport !== 'stdio') {
    throw new Error(`Unsupported transport: ${parsed.transport}`);
  }

  await runStdioServer(config);
}

const isEntrypoint =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isEntrypoint) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
