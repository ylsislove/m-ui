#!/usr/bin/env python3
"""Local web remote for Xiaomi TV's LAN API."""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen


DEFAULT_TV_IP = "192.168.1.100"
TV_PORT = 6095
REQUEST_TIMEOUT_SECONDS = 8
KEYCODES = {
    "power",
    "up",
    "down",
    "left",
    "right",
    "enter",
    "home",
    "back",
    "menu",
    "volumeup",
    "volumedown",
}
PACKAGE_NAME_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+$")


class ApiError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def validate_tv_ip(value: str) -> str:
    try:
        address = ipaddress.IPv4Address(value.strip())
    except ipaddress.AddressValueError as exc:
        raise ApiError("电视地址必须是有效的 IPv4 地址") from exc

    if not (address.is_private or address.is_loopback):
        raise ApiError("出于安全考虑，只允许访问局域网 IPv4 地址")
    return str(address)


def call_tv(tv_ip: str, path: str, params: dict[str, str]) -> dict[str, Any]:
    query = urlencode(params)
    url = f"http://{tv_ip}:{TV_PORT}{path}?{query}"
    request = Request(url, headers={"User-Agent": "Xiaomi-TV-Web-Remote/1.0"})
    started = time.monotonic()

    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except HTTPError as exc:
        raise ApiError(f"电视返回 HTTP {exc.code}", 502) from exc
    except (URLError, TimeoutError, OSError) as exc:
        reason = getattr(exc, "reason", exc)
        raise ApiError(f"无法连接电视：{reason}", 502) from exc

    try:
        result = json.loads(raw)
    except json.JSONDecodeError:
        result = {"raw": raw}

    return {
        "ok": True,
        "elapsed_ms": round((time.monotonic() - started) * 1000),
        "tv": result,
    }


class TvRemoteHandler(SimpleHTTPRequestHandler):
    server_version = "XiaomiTvRemote/1.0"

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length <= 0 or content_length > 65_536:
            raise ApiError("请求内容为空或过大")
        try:
            return json.loads(self.rfile.read(content_length))
        except json.JSONDecodeError as exc:
            raise ApiError("请求不是有效的 JSON") from exc

    def _handle_api(self) -> None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        tv_ip = validate_tv_ip(query.get("host", [DEFAULT_TV_IP])[0])

        if parsed.path == "/api/tv/info":
            self._send_json(200, call_tv(tv_ip, "/request", {"action": "isalive"}))
            return

        if parsed.path == "/api/tv/apps":
            self._send_json(
                200,
                call_tv(
                    tv_ip,
                    "/controller",
                    {"action": "getinstalledapp", "count": "999", "changeIcon": "1"},
                ),
            )
            return

        raise ApiError("接口不存在", 404)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/api/"):
            try:
                self._handle_api()
            except ApiError as exc:
                self._send_json(exc.status, {"ok": False, "error": str(exc)})
            except Exception as exc:  # pragma: no cover - last-resort boundary
                self._send_json(500, {"ok": False, "error": f"本地服务异常：{exc}"})
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        try:
            parsed = urlparse(self.path)
            body = self._read_json()
            tv_ip = validate_tv_ip(str(body.get("host", DEFAULT_TV_IP)))

            if parsed.path == "/api/tv/key":
                keycode = str(body.get("keycode", ""))
                if keycode not in KEYCODES:
                    raise ApiError("不支持这个按键")
                result = call_tv(
                    tv_ip,
                    "/controller",
                    {"action": "keyevent", "keycode": keycode},
                )
                self._send_json(200, result)
                return

            if parsed.path == "/api/tv/start-app":
                package_name = str(body.get("package", ""))
                if not PACKAGE_NAME_PATTERN.fullmatch(package_name):
                    raise ApiError("应用包名格式不正确")
                result = call_tv(
                    tv_ip,
                    "/controller",
                    {
                        "action": "startapp",
                        "type": "packagename",
                        "packagename": package_name,
                    },
                )
                self._send_json(200, result)
                return

            raise ApiError("接口不存在", 404)
        except ApiError as exc:
            self._send_json(exc.status, {"ok": False, "error": str(exc)})
        except Exception as exc:  # pragma: no cover - last-resort boundary
            self._send_json(500, {"ok": False, "error": f"本地服务异常：{exc}"})

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="小米电视局域网 Web 遥控器")
    parser.add_argument("--host", default="127.0.0.1", help="本地监听地址")
    parser.add_argument("--port", type=int, default=8765, help="本地监听端口")
    args = parser.parse_args()

    static_dir = Path(__file__).resolve().parent
    handler = partial(TvRemoteHandler, directory=str(static_dir))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"小米电视遥控器已启动：http://{args.host}:{args.port}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
