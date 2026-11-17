"""App-owned entry point for the bundled yt-dlp engine; no remote downloader."""

import ctypes
import io
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlsplit

_configured = False
_active_directory = None
_session = None
_session_cookies = None
_session_cache = None
_last_progress = 0


def run(request, navigation_callback):
    global _active_directory
    directory = Path(request["directory"])
    _active_directory = directory
    result = {}
    try:
        _diagnostic(directory, "Python initialisation", "Configuring SSL and challenge provider")
        _configure(navigation_callback)
        if request.get("action") == "verify":
            import ssl
            from yt_dlp.version import __version__
            from yt_dlp_plugins.extractor.ytjsc import AppleWebKitJCP
            from yt_dlp import YoutubeDL
            from yt_dlp_plugins.webkit_jsi.lib.logging import DefaultLoggerImpl

            assert ssl.OPENSSL_VERSION
            assert AppleWebKitJCP.JS_RUNTIME_NAME
            with YoutubeDL({"quiet": True, "cachedir": False}) as downloader:
                provider = AppleWebKitJCP(downloader.get_info_extractor("Youtube"), DefaultLoggerImpl(), {})
                try:
                    assert provider._lib_script.code and provider._core_script.code
                    output = provider._run_js_runtime('console.log(JSON.stringify({answer: 1 + 1}));')
                    assert json.loads(output) == {"answer": 2}
                finally:
                    provider.close()
            if request.get("fixture"):
                source = Path(request["fixture"])
                with YoutubeDL({"enable_file_urls": True, "quiet": True, "outtmpl": str(directory / "fixture.m4a")}) as downloader:
                    downloader.download([source.as_uri()])
                assert (directory / "fixture.m4a").read_bytes() == source.read_bytes()
            result["version"] = __version__
        else:
            _diagnostic(directory, "YouTube extraction", "Starting yt-dlp")
            result["duration"] = _download(request, directory)
            _diagnostic(directory, "Audio downloaded", "Returning audio for container normalization")
    except Exception as error:
        _diagnostic(directory, "Downloader error", str(error))
        result["error"] = str(error)
        if request.get("action") == "verify":
            import traceback
            result["error"] = traceback.format_exc()
    (directory / "result.json").write_text(json.dumps(result), encoding="utf-8")


def _configure(navigation_callback):
    global _configured
    sys.stdout = sys.stderr = io.StringIO()
    # Reloading plugins collides with existing challenge-provider registrations.
    if _configured:
        return
    import certifi
    from yt_dlp.plugins import load_all_plugins

    os.environ["SSL_CERT_FILE"] = certifi.where()
    load_all_plugins()
    from yt_dlp_plugins.extractor.ytjsc import AppleWebKitJCP

    # The upstream Apache-2.0 provider exposes its owned WKWebView. Attach our
    # delegate after initial creation; do not copy Palladium's GPL patch.
    original = getattr(AppleWebKitJCP, "_c0snow_original_webview", None)
    if original is None:
        original = AppleWebKitJCP._get_webview_lazy
        AppleWebKitJCP._c0snow_original_webview = original
    restrict = ctypes.CFUNCTYPE(None, ctypes.c_size_t)(navigation_callback)

    def webview(provider):
        _diagnostic(_active_directory, "WebKit challenge", "Creating the JavaScript runtime")
        view = original(provider)
        restrict(view._wv)
        return view

    AppleWebKitJCP._get_webview_lazy = webview
    original_runtime = AppleWebKitJCP._run_js_runtime

    def runtime(provider, *args, **kwargs):
        _diagnostic(_active_directory, "WebKit challenge", "Evaluating the YouTube JavaScript challenge")
        result = original_runtime(provider, *args, **kwargs)
        _diagnostic(_active_directory, "WebKit challenge finished", "JavaScript evaluation returned")
        return result

    AppleWebKitJCP._run_js_runtime = runtime
    _configured = True


def _download(request, directory):
    from yt_dlp.utils import DownloadError

    global _active_directory, _last_progress
    _active_directory = directory
    _last_progress = 0
    if (directory / "cancel").exists():
        raise DownloadError("Download cancelled")
    downloader = _download_session(request, directory)
    downloader.params["outtmpl"]["default"] = str(directory / "audio.%(ext)s")
    try:
        info = downloader.extract_info("https://m.youtube.com/watch?v=" + request["video_id"], download=True)
        if not (directory / "audio.m4a").is_file():
            raise DownloadError("No compatible M4A audio was downloaded")
        return info["duration"]
    except Exception:
        _close_session()
        raise


def _download_session(request, directory):
    global _session, _session_cookies, _session_cache
    from http.cookiejar import Cookie
    from yt_dlp import YoutubeDL

    records = json.loads(request.get("cookies", "[]"))
    cache = request["extractor_cache"]
    if _session is not None and records == _session_cookies and cache == _session_cache:
        _diagnostic(directory, "Extractor session", "Reusing player JavaScript and challenge runtime")
        return _session
    _close_session()
    # yt-dlp keeps player source in the extractor instance, not its disk cache.
    # Reference: yt-dlp/yt-dlp 2026.10.26, YoutubeIE._load_player.
    downloader = YoutubeDL({
        "format": "bestaudio[ext=m4a][vcodec=none]",
        "outtmpl": str(directory / "audio.%(ext)s"),
        "noplaylist": True,
        "max_filesize": 500_000_000,
        "socket_timeout": 20,
        "retries": 2,
        "fragment_retries": 2,
        "cachedir": cache,
        "quiet": True,
        "noprogress": True,
        "progress_hooks": [_download_progress],
        "logger": _DiagnosticLogger(),
    })
    try:
        for record in records:
            expires = record.get("expires")
            downloader.cookiejar.set_cookie(Cookie(
                version=0, name=record["name"], value=record["value"],
                port=None, port_specified=False, domain=record["domain"],
                domain_specified=True, domain_initial_dot=record["domain"].startswith("."),
                path=record["path"], path_specified=True, secure=record["secure"],
                expires=int(expires) if expires is not None else None,
                discard=expires is None, comment=None, comment_url=None,
                rest={"HttpOnly": None} if record["httpOnly"] else {},
            ))
    except Exception:
        downloader.close()
        raise
    _session, _session_cookies, _session_cache = downloader, records, cache
    _diagnostic(directory, "Extractor session", "Created session with persistent extractor cache")
    return downloader


def _close_session():
    global _session, _session_cookies, _session_cache
    previous = _session
    _session = _session_cookies = _session_cache = None
    if previous is not None:
        previous.close()


def _download_progress(status):
    global _last_progress
    from yt_dlp.utils import DownloadError

    if (_active_directory / "cancel").exists():
        raise DownloadError("Download cancelled")
    if status.get("downloaded_bytes", 0) > 500_000_000:
        raise DownloadError("Audio exceeds 500 MB")
    now = time.monotonic()
    if now - _last_progress >= 1 or status.get("status") == "finished":
        downloaded = status.get("downloaded_bytes", 0)
        total = status.get("total_bytes") or status.get("total_bytes_estimate")
        _diagnostic(_active_directory, "Downloading audio", f"{downloaded} bytes received" + (f" / {total} bytes" if total else ""))
        _last_progress = now


def _diagnostic(directory, stage, message):
    # Only diagnostics are redacted; this never modifies requests or account cookies.
    message = re.sub(r"https?://[^\s<>\"']+", lambda match: "https://" + (urlsplit(match.group()).hostname or "redacted-url") + "/<redacted>", message)
    message = re.sub(r"(?im)\b(authorization|cookie|set-cookie|x-api-key|x-admin-key)\s*[:=][^\r\n]*", "<redacted>", message)
    message = re.sub(r"(?i)\bBearer\s+[^\s,;]+", "<redacted>", message)
    with (directory / "diagnostics.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({"stage": stage, "message": message[:800]}) + "\n")


class _DiagnosticLogger:
    def __init__(self, directory=None):
        self._directory = directory

    @property
    def directory(self):
        return self._directory or _active_directory

    def debug(self, message):
        if not message.startswith("[debug]"):
            _diagnostic(self.directory, "YouTube extraction", message)

    def warning(self, message):
        _diagnostic(self.directory, "YouTube warning", message)

    def error(self, message):
        _diagnostic(self.directory, "YouTube error", message)
