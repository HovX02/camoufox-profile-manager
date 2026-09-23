"""Integration tests for the VNC WebSocket proxy."""

import asyncio

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from camoufox_pm.main import app


def test_vnc_proxy_unreachable_server(monkeypatch):
    """Test /vnc/ws when VNC server on port 5900 is unreachable."""
    async def mock_open_connection(host, port):
        raise ConnectionRefusedError("Connection refused")

    monkeypatch.setattr(asyncio, "open_connection", mock_open_connection)

    client = TestClient(app)
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect("/vnc/ws") as ws:
            ws.receive_bytes()
    assert exc_info.value.code == 1011


def test_vnc_proxy_reachable_server(monkeypatch):
    """Test /vnc/ws when a VNC server is reachable on port 5900."""
    written_bytes = bytearray()

    class MockReader:
        def __init__(self):
            self.data_chunks = [b"RFB 003.008\n"]

        async def read(self, n):
            if self.data_chunks:
                return self.data_chunks.pop(0)
            await asyncio.sleep(10)
            return b""

    class MockWriter:
        def write(self, data):
            written_bytes.extend(data)

        async def drain(self):
            pass

        def close(self):
            pass

        async def wait_closed(self):
            pass

    reader = MockReader()
    writer = MockWriter()

    async def mock_open_connection(host, port):
        return reader, writer

    monkeypatch.setattr(asyncio, "open_connection", mock_open_connection)

    client = TestClient(app)
    with client.websocket_connect("/vnc/ws", headers={"sec-websocket-protocol": "binary"}) as ws:
        ws.send_bytes(b"CLIENT RFB INIT")
        data = ws.receive_bytes()
        assert data == b"RFB 003.008\n"
        # Small delay to allow ws_to_tcp task in background to drain
        ws.close()
        assert written_bytes == b"CLIENT RFB INIT"


def test_vnc_proxy_handles_text_messages(monkeypatch):
    """Test /vnc/ws handles text frames gracefully without crashing."""
    written_bytes = bytearray()

    class MockReader:
        def __init__(self):
            self.data_chunks = [b"OK\n"]

        async def read(self, n):
            if self.data_chunks:
                return self.data_chunks.pop(0)
            await asyncio.sleep(10)
            return b""

    class MockWriter:
        def write(self, data):
            written_bytes.extend(data)

        async def drain(self):
            pass

        def close(self):
            pass

        async def wait_closed(self):
            pass

    reader = MockReader()
    writer = MockWriter()

    async def mock_open_connection(host, port):
        return reader, writer

    monkeypatch.setattr(asyncio, "open_connection", mock_open_connection)

    client = TestClient(app)
    with client.websocket_connect("/vnc/ws") as ws:
        ws.send_text("TEXT FRAME DATA")
        data = ws.receive_bytes()
        assert data == b"OK\n"
        ws.close()
        assert written_bytes == b"TEXT FRAME DATA"
