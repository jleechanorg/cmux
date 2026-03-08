# cmux MCP Server Recommendation

Last updated: March 7, 2026

## Recommendation

Build a local MCP server for cmux, but keep it as a thin adapter over the existing v2 Unix socket API instead of adding a second control plane inside the app.

This is justified because cmux already exposes most of the primitives an MCP host would need:

1. `TerminalController` already implements a JSON v2 socket protocol with stable methods for `window.*`, `workspace.*`, `pane.*`, `surface.*`, and `browser.*` in [TerminalController.swift](/tmp/cmux-mcp-worktree/Sources/TerminalController.swift).
2. `system.tree` and `system.identify` already provide the discovery and self-location data an agent needs to reason about windows, workspaces, panes, and surfaces.
3. `TabManager`, `Workspace`, and `AppDelegate` already own the real mutations for selection, creation, moving, focusing, and cross-window routing, so an MCP server does not need to replicate that logic.

## Codebase Findings

### Existing control plane

1. `TerminalController` is already the automation boundary:
   - capability advertisement via `v2Capabilities()`
   - hierarchy discovery via `v2SystemTree()`
   - window/workspace/surface/pane/browser dispatch in the `window.*`, `workspace.*`, `surface.*`, `pane.*`, and `browser.*` handlers
2. `AppDelegate` already exposes window-level lookup and mutation:
   - `listMainWindowSummaries()`
   - `tabManagerFor(windowId:)`
   - `focusMainWindow(windowId:)`
   - `createMainWindow()`
   - `closeMainWindow(windowId:)`
3. `TabManager` already owns workspace lifecycle and selection:
   - `addWorkspace()`
   - `selectWorkspace(_:)`
   - `reorderWorkspace(...)`
   - workspace title/color/pin operations
4. `Workspace` already owns pane and surface topology:
   - bonsplit pane state
   - panel registry
   - focused surface tracking
   - terminal/browser surface metadata

### Design implication

The app already has a useful "cmux control kernel". The missing piece is a host-friendly MCP facade, not more app-side orchestration code.

## Proposed Architecture

Run the MCP server as an external local stdio process:

1. MCP host starts `scripts/cmux_mcp_server.py`.
2. The server connects to the configured cmux socket (`CMUX_SOCKET_PATH` or `--socket`).
3. MCP tools translate directly to v2 socket calls.
4. `TerminalController` remains the source of truth for capability routing and object identity.

Why external is better than embedding inside cmux:

1. MCP is a transport/protocol concern; cmux already has the stateful control API.
2. External stdio avoids mixing MCP lifecycle with AppKit lifecycle.
3. The same adapter can target different cmux sockets without changing the app.
4. The adapter can stay intentionally small and experimental while the socket API evolves.

## Initial Tool Set

Recommend exposing a narrow first pass instead of mirroring every socket method one-for-one.

### Discovery

1. `cmux_socket_discover`
   - Find candidate local cmux sockets under `/tmp`.
2. `cmux_system_tree`
   - Return windows, workspaces, panes, surfaces, and the active path.

### Workspace steering

1. `cmux_list_workspaces`
2. `cmux_create_workspace`
3. `cmux_select_workspace`

### Surface steering

1. `cmux_list_surfaces`
2. `cmux_send_text`
3. `cmux_read_text`

### Escape hatch

1. `cmux_socket_call`
   - Raw pass-through to an existing v2 socket method.
   - Useful while validating which abstractions should become first-class MCP tools.

## What Not To Build Yet

1. Do not duplicate the entire `window.*` / `workspace.*` / `surface.*` / `browser.*` matrix as separate MCP tools yet.
2. Do not add a second IPC path inside cmux just for MCP.
3. Do not invent new object IDs; reuse cmux UUID/ref handles from the socket API.
4. Do not let the MCP layer bypass `TerminalController` focus rules or socket auth/access mode.

## Risks and Guardrails

1. Focus-stealing remains an app concern. The MCP adapter should respect the focus policies already enforced by `TerminalController`.
2. Socket auth mode matters. If the socket is password-protected or disabled, MCP should fail clearly instead of trying to bypass it.
3. Tool count can explode quickly. Keep MCP tools task-shaped and leave uncommon operations behind `cmux_socket_call` until repeated usage proves they deserve dedicated schemas.

## Recommendation Summary

Yes, build the MCP server.

But build it as:

1. an external stdio adapter
2. backed by the existing v2 socket API
3. with a small, high-value tool surface first
4. and a raw-call escape hatch while the tool taxonomy settles
