"""App-owned entry point for the bundled yt-dlp engine; no remote downloader."""

import ctypes
import io
import json
import os
from pathlib import Path
import sys


def run(request, navigation_callback):
    directory = Path(request["directory"])
    result = {}
    try:
        _configure(navigation_callback)
        if request.get("action") == "verify":
            import ssl
            from yt_dlp.version import __version__
            from yt_dlp_plugins.extractor.ytjsc import AppleWebKitJCP
            from yt_dlp_plugins.webkit_jsi.lib.easy import WKJSE_Factory, WKJSE_Webview
            from yt_dlp_plugins.webkit_jsi.lib.logging import DefaultLoggerImpl

            assert ssl.OPENSSL_VERSION
            assert AppleWebKitJCP.JS_RUNTIME_NAME
            with WKJSE_Factory(DefaultLoggerImpl()) as send:
                with WKJSE_Webview(send) as view:
                    assert view.execute_js("1 + 1") == 2
            result["version"] = __version__
        else:
            _download(request, directory)
    except Exception as error:
        result["error"] = str(error)
    (directory / "result.json").write_text(json.dumps(result), encoding="utf-8")


def _configure(navigation_callback):
    import certifi
    from yt_dlp.plugins import load_all_plugins

    os.environ["SSL_CERT_FILE"] = certifi.where()
    sys.stdout = sys.stderr = io.StringIO()
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
        view = original(provider)
        restrict(view._wv)
        return view

    AppleWebKitJCP._get_webview_lazy = webview


def _download(request, directory):
    from yt_dlp import YoutubeDL
    from yt_dlp.utils import DownloadError

    def progress(status):
        if (directory / "cancel").exists():
            raise DownloadError("Download cancelled")
        if status.get("downloaded_bytes", 0) > 500_000_000:
            raise DownloadError("Audio exceeds 500 MB")

    options = {
        "format": "bestaudio[ext=m4a][vcodec=none]",
        "outtmpl": str(directory / "audio.%(ext)s"),
        "noplaylist": True,
        "max_filesize": 500_000_000,
        "socket_timeout": 20,
        "retries": 2,
        "fragment_retries": 2,
        "cachedir": False,
        "quiet": True,
        "noprogress": True,
        "progress_hooks": [progress],
    }
    with YoutubeDL(options) as downloader:
        downloader.download(["https://m.youtube.com/watch?v=" + request["video_id"]])
    if not (directory / "audio.m4a").is_file():
        raise DownloadError("No compatible M4A audio was downloaded")
