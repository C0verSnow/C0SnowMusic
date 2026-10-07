#!/usr/bin/env bash
# Run the remote-CI-built deb on the designated ARM64 server. Never builds/tests.
set -euo pipefail
cd /home/C0SnowMusic
if [[ $(id -u) != 0 ]]; then
  echo '请使用 root 启动这个服务器专用脚本。' >&2
  exit 1
fi
command -v c0snowmusic >/dev/null
command -v Xvfb >/dev/null
command -v pulseaudio >/dev/null
if ! id c0snowmusic >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/C0SnowMusic/.desktop --shell /usr/sbin/nologin c0snowmusic
fi
app_uid=$(id -u c0snowmusic)
install -d -m 700 -o c0snowmusic -g c0snowmusic "/run/user/$app_uid"
install -d -m 700 -o c0snowmusic -g c0snowmusic /home/C0SnowMusic/evidence
if [[ ! -S /tmp/.X11-unix/X99 ]]; then
  Xvfb :99 -screen 0 1440x1000x24 -nolisten tcp -ac > /home/C0SnowMusic/xvfb.log 2>&1 &
  sleep 2
fi
# Virtual output: proves decoding/progress; does not claim physical speaker output.
exec runuser -u c0snowmusic -- env DISPLAY=:99 XDG_RUNTIME_DIR="/run/user/$app_uid" \
  dbus-run-session -- bash -c '
    pulseaudio --start --exit-idle-time=-1
    pactl load-module module-null-sink sink_name=c0verification >/dev/null
    pactl set-default-sink c0verification
    exec c0snowmusic --no-sandbox --disable-gpu --autoplay-policy=no-user-gesture-required \
      --bilibili --bilibili-autoplay --evidence-dir=/home/C0SnowMusic/evidence
  '
