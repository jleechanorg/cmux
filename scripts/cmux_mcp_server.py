#!/usr/bin/env python3
"""Minimal MCP adapter for cmux's existing v2 Unix socket API."""

from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
TESTS_V2_DIR = REPO_ROOT / "tests_v2"
if str(TESTS_V2_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_V2_DIR))

from cmux import cmux, cmuxError  # noqa: E402


SERVER_NAME = "cmux-mcp"
SERVER_VERSION = "0.1.0"


def _json_default(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


class McpProtocolError(Exception):
    pass


class CmuxMcpServer:
    def __init__(self, socket_path: str | None = None) -> None:
        self.socket_path = socket_path
        self._protocol_version = "2024-11-05"

    def serve(self) -> int:
        while True:
            message = self._read_message()
            if message is None:
                return 0
            self._handle_message(message)

    def _read_message(self) -> dict[str, Any] | None:
        headers: dict[str, str] = {}

        while True:
            line = sys.stdin.buffer.readline()
            if not line:
                if headers:
                    raise McpProtocolError("Unexpected EOF while reading MCP headers")
                return None
            if line in (b"\r\n", b"\n"):
                break
            decoded = line.decode("utf-8").strip()
            if ":" not in decoded:
                raise McpProtocolError(f"Invalid header line: {decoded!r}")
            key, value = decoded.split(":", 1)
            headers[key.strip().lower()] = value.strip()

        content_length = headers.get("content-length")
        if content_length is None:
            raise McpProtocolError("Missing Content-Length header")
        try:
            content_length_value = int(content_length)
        except ValueError as exc:
            raise McpProtocolError(
                f"Invalid Content-Length header: {content_length!r}"
            ) from exc
        if content_length_value < 0:
            raise McpProtocolError(
                f"Negative Content-Length not allowed: {content_length!r}"
            )

        body = sys.stdin.buffer.read(content_length_value)
        if len(body) != content_length_value:
            raise McpProtocolError("Unexpected EOF while reading MCP body")

        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, dict):
            raise McpProtocolError("Expected JSON object payload")
        return payload

    def _write_message(self, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, separators=(",", ":"), default=_json_default).encode("utf-8")
        sys.stdout.buffer.write(f"Content-Length: {len(encoded)}\r\n\r\n".encode("ascii"))
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()

    def _write_response(self, request_id: Any, result: dict[str, Any]) -> None:
        self._write_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result,
        })

    def _write_error(self, request_id: Any, code: int, message: str, data: Any = None) -> None:
        error: dict[str, Any] = {"code": code, "message": message}
        if data is not None:
            error["data"] = data
        self._write_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": error,
        })

    def _handle_message(self, message: dict[str, Any]) -> None:
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params") or {}

        try:
            if method == "initialize":
                if request_id is None:
                    return
                requested_version = params.get("protocolVersion")
                if isinstance(requested_version, str) and requested_version:
                    if requested_version != self._protocol_version:
                        self._write_error(
                            request_id,
                            -32602,
                            f"Unsupported protocolVersion: {requested_version}",
                        )
                        return
                self._write_response(request_id, self._initialize_result())
                return

            if method == "notifications/initialized":
                return

            if method == "ping":
                if request_id is None:
                    return
                self._write_response(request_id, {})
                return

            if method == "tools/list":
                if request_id is None:
                    return
                self._write_response(request_id, {"tools": self._tools()})
                return

            if method == "tools/call":
                if request_id is None:
                    return
                name = params.get("name")
                arguments = params.get("arguments") or {}
                result = self._call_tool(name, arguments)
                self._write_response(request_id, result)
                return

            if request_id is not None:
                self._write_error(request_id, -32601, f"Method not found: {method}")
        except cmuxError as exc:
            if request_id is not None:
                self._write_error(request_id, -32001, str(exc))
        except McpProtocolError:
            raise
        except Exception as exc:  # pragma: no cover - defensive scaffold
            if request_id is not None:
                self._write_error(
                    request_id,
                    -32603,
                    f"Internal error: {exc}",
                    {"traceback": traceback.format_exc(limit=8)},
                )

    def _initialize_result(self) -> dict[str, Any]:
        return {
            "protocolVersion": self._protocol_version,
            "serverInfo": {
                "name": SERVER_NAME,
                "version": SERVER_VERSION,
            },
            "capabilities": {
                "tools": {},
            },
        }

    def _tools(self) -> list[dict[str, Any]]:
        return [
            {
                "name": "cmux_socket_discover",
                "description": "List candidate local cmux Unix sockets under /tmp.",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_system_tree",
                "description": "Return the active cmux hierarchy: windows, workspaces, panes, and surfaces.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "workspace_id": {"type": "string"},
                        "all_windows": {"type": "boolean"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_list_workspaces",
                "description": "List workspaces for the current socket or a specific window.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "window_id": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_create_workspace",
                "description": "Create a workspace, optionally in a target window, and optionally rename it.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "window_id": {"type": "string"},
                        "title": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_select_workspace",
                "description": "Select a workspace by UUID or cmux workspace ref.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "workspace_id": {"type": "string"},
                    },
                    "required": ["workspace_id"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_list_surfaces",
                "description": "List surfaces in the current workspace or a specific workspace.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "workspace_id": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_send_text",
                "description": "Send text to the focused surface or a specific surface.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "surface_id": {"type": "string"},
                        "text": {"type": "string"},
                    },
                    "required": ["text"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_read_text",
                "description": "Read visible terminal text from the focused surface or a specific surface.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "workspace_id": {"type": "string"},
                        "surface_id": {"type": "string"},
                        "scrollback": {"type": "boolean"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "cmux_socket_call",
                "description": "Call any existing cmux v2 socket method directly.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "method": {"type": "string"},
                        "params": {"type": "object"},
                    },
                    "required": ["method"],
                    "additionalProperties": False,
                },
            },
        ]

    def _call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        handlers = {
            "cmux_socket_discover": self._tool_socket_discover,
            "cmux_system_tree": self._tool_system_tree,
            "cmux_list_workspaces": self._tool_list_workspaces,
            "cmux_create_workspace": self._tool_create_workspace,
            "cmux_select_workspace": self._tool_select_workspace,
            "cmux_list_surfaces": self._tool_list_surfaces,
            "cmux_send_text": self._tool_send_text,
            "cmux_read_text": self._tool_read_text,
            "cmux_socket_call": self._tool_socket_call,
        }
        handler = handlers.get(name)
        if handler is None:
            raise cmuxError(f"Unknown tool: {name}")
        payload = handler(arguments)
        return self._tool_result(payload)

    def _client(self) -> cmux:
        client = cmux(self.socket_path) if self.socket_path else cmux()
        client.connect()
        return client

    def _tool_socket_discover(self, _: dict[str, Any]) -> dict[str, Any]:
        sockets = []
        for path in sorted(Path("/tmp").glob("cmux*.sock")):
            sockets.append({
                "path": str(path),
                "exists": path.exists(),
                "is_socket": path.is_socket(),
            })
        return {
            "default_socket_path": self.socket_path or cmux.DEFAULT_SOCKET_PATH,
            "sockets": sockets,
        }

    def _tool_system_tree(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if "workspace_id" in arguments:
            params["workspace_id"] = arguments["workspace_id"]
        if "all_windows" in arguments:
            params["all_windows"] = bool(arguments["all_windows"])
        with self._client() as client:
            result = client._call("system.tree", params)
            return dict(result or {})

    def _tool_list_workspaces(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if "window_id" in arguments:
            params["window_id"] = arguments["window_id"]
        with self._client() as client:
            result = client._call("workspace.list", params)
            return dict(result or {})

    def _tool_create_workspace(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if "window_id" in arguments:
            params["window_id"] = arguments["window_id"]
        with self._client() as client:
            create_result = dict(client._call("workspace.create", params) or {})
            workspace_id = create_result.get("workspace_id")
            title = (arguments.get("title") or "").strip()
            if workspace_id and title:
                client._call("workspace.rename", {
                    "workspace_id": workspace_id,
                    "title": title,
                })
                create_result["title"] = title
            return create_result

    def _tool_select_workspace(self, arguments: dict[str, Any]) -> dict[str, Any]:
        workspace_id = str(arguments["workspace_id"]).strip()
        with self._client() as client:
            result = client._call("workspace.select", {"workspace_id": workspace_id})
            return dict(result or {})

    def _tool_list_surfaces(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if "workspace_id" in arguments:
            params["workspace_id"] = arguments["workspace_id"]
        with self._client() as client:
            result = client._call("surface.list", params)
            return dict(result or {})

    def _tool_send_text(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params = {"text": str(arguments["text"])}
        if "surface_id" in arguments:
            params["surface_id"] = str(arguments["surface_id"]).strip()
        with self._client() as client:
            result = client._call("surface.send_text", params)
            return dict(result or {})

    def _tool_read_text(self, arguments: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if "workspace_id" in arguments:
            params["workspace_id"] = arguments["workspace_id"]
        if "surface_id" in arguments:
            params["surface_id"] = arguments["surface_id"]
        if "scrollback" in arguments:
            params["scrollback"] = bool(arguments["scrollback"])
        with self._client() as client:
            result = client._call("surface.read_text", params)
            return dict(result or {})

    def _tool_socket_call(self, arguments: dict[str, Any]) -> dict[str, Any]:
        method = str(arguments["method"]).strip()
        params = arguments.get("params") or {}
        if not isinstance(params, dict):
            raise cmuxError("cmux_socket_call.params must be an object")
        with self._client() as client:
            result = client._call(method, params)
            if isinstance(result, dict):
                return result
            return {"value": result}

    def _tool_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        pretty = json.dumps(payload, indent=2, sort_keys=True, default=_json_default)
        return {
            "content": [
                {
                    "type": "text",
                    "text": pretty,
                }
            ],
            "structuredContent": payload,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="cmux MCP stdio adapter")
    parser.add_argument(
        "--socket",
        default=os.environ.get("CMUX_SOCKET_PATH"),
        help="Override the cmux Unix socket path.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    server = CmuxMcpServer(socket_path=args.socket)
    return server.serve()


if __name__ == "__main__":
    raise SystemExit(main())
