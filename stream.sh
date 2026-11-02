#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# SXB relay supervisor
# LIVE video is passed through without scaling, FPS conversion or video re-encoding.
# Only the standby slate is generated at 1920x1080 @ 60 FPS.

STREAMER="${STREAMER:-SXB}"
TITLE_AR="${TITLE_AR:-توقف البث من شونق}"
SUBTITLE_AR="${SUBTITLE_AR:-جاري الانتظار...}"
LOGO_URL="${LOGO_URL:-}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

: "${RESTREAM_KEY:?Missing GitHub secret RESTREAM_KEY}"
if [[ ! "$RESTREAM_KEY" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "ERROR: RESTREAM_KEY contains unexpected characters."
  exit 1
fi

RESTREAM_URL="rtmp://live.restream.io/live/${RESTREAM_KEY}"
KICK_URL="https://kick.com/${STREAMER}"

FIFO="/tmp/sxb-relay.ts"
WORKDIR="/tmp/sxb-standby"
STANDBY_TS="$WORKDIR/standby.ts"
OUT_PROGRESS="/tmp/sxb-out.progress"
OUT_LOG="/tmp/sxb-out.log"
PROD_LOG="/tmp/sxb-prod.log"
STREAMLINK_LOG="/tmp/sxb-streamlink.log"
KEEPER_READY="/tmp/sxb-keeper.ready"

WIDTH=1920
HEIGHT=1080
FPS=60
GOP=120

AAC_ARGS=(-c:a aac -b:a 160k -ar 48000 -ac 2)

OUT=""
PROD=""
KEEPER=""
MODE="UNKNOWN"
LIVE_FAILS=0
LAST_STATUS_CHECK=0
OUT_LAST_FRAME=""
OUT_LAST_ADVANCE_AT=0
GRACE_UNTIL=0

log() {
  printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"
}

is_pid_alive() {
  [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null
}

stop_group() {
  local pid="${1:-}"
  local i

  [[ -n "$pid" ]] || return 0

  kill -TERM -- "-${pid}" 2>/dev/null ||
    kill -TERM "$pid" 2>/dev/null || true

  for ((i=0; i<25; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if kill -0 -- "-${pid}" 2>/dev/null; then
    kill -KILL -- "-${pid}" 2>/dev/null || true
  elif kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi

  wait "$pid" 2>/dev/null || true
}

stop_producer() {
  if [[ -n "$PROD" ]]; then
    stop_group "$PROD"
    PROD=""
  fi
}

stop_output() {
  if [[ -n "$OUT" ]]; then
    stop_group "$OUT"
    OUT=""
  fi
}

stop_keeper() {
  if [[ -n "$KEEPER" ]]; then
    stop_group "$KEEPER"
    KEEPER=""
  fi
}

cleanup() {
  trap - EXIT INT TERM
  log "Stopping relay processes..."
  stop_producer
  stop_output
  stop_keeper
  rm -f "$KEEPER_READY"
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

progress_value() {
  local file="$1"
  local key="$2"

  [[ -s "$file" ]] || return 0

  tail -n 40 "$file" 2>/dev/null |
    awk -F= -v wanted="$key" \
      '$1 == wanted { value=$2 } END { if (value != "") print value }' || true
}

normalize_number() {
  local value="${1:-}"
  value="${value//[[:space:]]/}"

  [[ "$value" =~ ^[0-9]+$ ]] &&
    printf '%s' "$value" ||
    printf '0'
}

show_producer_diagnostics() {
  echo "----- producer log (last 35 lines) -----"
  tail -n 35 "$PROD_LOG" 2>/dev/null || true

  echo "----- Streamlink log (last 35 lines) -----"
  tail -n 35 "$STREAMLINK_LOG" 2>/dev/null || true
}

show_output_diagnostics() {
  echo "----- output log (last 35 lines) -----"
  tail -n 35 "$OUT_LOG" 2>/dev/null || true
}

make_standby() {
  mkdir -p "$WORKDIR"
  log "Creating standby artwork..."

  cat > "$WORKDIR/make_ui.py" <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import io, os, urllib.request

W = int(os.environ.get("WIDTH", "1920"))
H = int(os.environ.get("HEIGHT", "1080"))
workdir = os.environ["WORKDIR"]
font_path = os.path.expanduser("~/.fonts/Cairo.ttf")

if not os.path.isfile(font_path):
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

title = os.environ.get("TITLE_AR", "توقف البث")
subtitle = os.environ.get("SUBTITLE_AR", "جاري الانتظار...")
streamer = os.environ.get("STREAMER", "SXB")
logo_url = os.environ.get("LOGO_URL", "")

def get_font(size):
    try:
        f = ImageFont.truetype(font_path, size)
        try:
            axes = f.get_variation_axes()
            if len(axes) == 1:
                f.set_variation_by_axes([700])
        except Exception:
            pass
        return f
    except Exception:
        return ImageFont.load_default()

def draw_rtl(draw, xy, text, font, fill):
    try:
        draw.text(
            xy, text, font=font, fill=fill,
            anchor="mm", direction="rtl", language="ar"
        )
    except Exception:
        draw.text(xy, text, font=font, fill=fill, anchor="mm")

bg = Image.new("RGB", (W, H))
pix = bg.load()

for y in range(H):
    t = y / max(1, H - 1)
    row = (int(20 - 12*t), int(10 - 7*t), int(18 - 12*t))
    for x in range(W):
        pix[x, y] = row

bg = bg.convert("RGBA")

glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((250, 70, 1030, 650), fill=(170, 12, 28, 75))
bg = Image.alpha_composite(
    bg, glow.filter(ImageFilter.GaussianBlur(115))
)

d = ImageDraw.Draw(bg)
d.rounded_rectangle(
    (55, 45, W-55, H-45),
    radius=24,
    fill=(13, 10, 15, 175),
    outline=(190, 35, 48, 175),
    width=2
)
d.rounded_rectangle(
    (68, 58, W-68, H-58),
    radius=18,
    outline=(255, 255, 255, 28),
    width=1
)

if logo_url:
    try:
        req = urllib.request.Request(
            logo_url,
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=8) as response:
            logo = Image.open(
                io.BytesIO(response.read())
            ).convert("RGBA")

        logo.thumbnail((115, 115), Image.Resampling.LANCZOS)
        bg.alpha_composite(
            logo, ((W-logo.width)//2, 88)
        )
    except Exception:
        pass

d = ImageDraw.Draw(bg)
d.rounded_rectangle(
    (W//2-95, 235, W//2+95, 242),
    radius=3,
    fill=(220, 35, 52, 230)
)

draw_rtl(
    d, (W//2, 335), title,
    get_font(64), (255, 255, 255, 255)
)

draw_rtl(
    d, (W//2, 420), subtitle,
    get_font(31), (220, 215, 220, 255)
)

d.text(
    (W//2, 545),
    streamer,
    font=get_font(72),
    fill=(235, 45, 58, 255),
    anchor="mm"
)

bg.convert("RGB").save(
    os.path.join(workdir, "standby.png"),
    quality=95
)
PYEOF

  WORKDIR="$WORKDIR" WIDTH="$WIDTH" HEIGHT="$HEIGHT" \
  STREAMER="$STREAMER" TITLE_AR="$TITLE_AR" \
  SUBTITLE_AR="$SUBTITLE_AR" LOGO_URL="$LOGO_URL" \
    python3 "$WORKDIR/make_ui.py"

  log "Encoding standby slate (1920x1080 @ 60 FPS, H.264/AAC)..."

  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate "$FPS" -i "$WORKDIR/standby.png" \
    -f lavfi -i "anullsrc=r=48000:cl=stereo" \
    -t 6 -map 0:v:0 -map 1:a:0 \
    -vf "format=yuv420p" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -pix_fmt yuv420p -r 60 -g 120 -keyint_min 120 \
    -threads 2 \
    "${AAC_ARGS[@]}" \
    -mpegts_flags +resend_headers+initial_discontinuity \
    -f mpegts "$STANDBY_TS"

  [[ -s "$STANDBY_TS" ]] || {
    log "ERROR: standby.ts was not created."
    return 1
  }

  ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height \
    -of default=noprint_wrappers=1 \
    "$STANDBY_TS" > /tmp/sxb-standby-probe.txt

  grep -q '^codec_name=h264$' /tmp/sxb-standby-probe.txt || {
    log "ERROR: standby video is not H.264."
    cat /tmp/sxb-standby-probe.txt
    return 1
  }

  log "Standby video validated."
}

setup_fifo() {
  # Only call after producer, output and keeper have stopped.
  rm -f "$FIFO" "$KEEPER_READY"
  mkfifo -m 600 "$FIFO"
}

start_output() {
  rm -f "$OUT_PROGRESS"
  : > "$OUT_LOG"

  log "Starting the persistent Restream output..."

  setsid ffmpeg -hide_banner -loglevel warning -nostdin \
    -thread_queue_size 1024 \
    -fflags +genpts+discardcorrupt \
    -probesize 100000 -analyzeduration 1000000 \
    -stats_period 1 -progress "$OUT_PROGRESS" \
    -f mpegts -i "$FIFO" \
    -map 0:v:0 -map 0:a:0? \
    -c:v copy -c:a copy \
    -max_muxing_queue_size 2048 \
    -flvflags no_duration_filesize -rtmp_live live \
    -flush_packets 1 \
    -f flv "$RESTREAM_URL" \
    >/dev/null 2>"$OUT_LOG" &

  OUT=$!

  sleep 0.5

  if ! is_pid_alive "$OUT"; then
    log "ERROR: output FFmpeg failed at startup."
    show_output_diagnostics

    local rc=0
    wait "$OUT" || rc=$?
    log "Output FFmpeg exit code: $rc"

    OUT=""
    return 1
  fi
}

start_keeper() {
  rm -f "$KEEPER_READY"

  # Keep a FIFO writer descriptor open during producer transitions.
  setsid bash -c '
    exec 3>"$1" || exit 1
    : > "$2"
    exec sleep infinity
  ' _ "$FIFO" "$KEEPER_READY" \
    >/tmp/sxb-keeper.log 2>&1 &

  KEEPER=$!

  local i
  for ((i=0; i<100; i++)); do
    if [[ -f "$KEEPER_READY" ]]; then
      if ! is_pid_alive "$OUT"; then
        log "ERROR: output died while opening the FIFO."
        stop_keeper
        return 1
      fi
      return 0
    fi

    if ! is_pid_alive "$OUT"; then
      log "ERROR: output exited before the FIFO keeper connected."
      stop_keeper
      return 1
    fi

    sleep 0.1
  done

  log "ERROR: FIFO keeper could not connect to the output reader."
  stop_keeper
  return 1
}

wait_for_output_advance() {
  local baseline="$1"
  local timeout_seconds="$2"
  local i frame

  for ((i=0; i<timeout_seconds; i++)); do
    frame="$(normalize_number "$(progress_value "$OUT_PROGRESS" frame)")"

    if (( frame > baseline )); then
      return 0
    fi

    if ! is_pid_alive "$OUT"; then
      log "ERROR: Output FFmpeg exited while waiting for incoming video."

      show_output_diagnostics
      show_producer_diagnostics

      local rc=0
      wait "$OUT" || rc=$?
      log "Output FFmpeg exit code: $rc"

      OUT=""
      return 1
    fi

    sleep 1
  done

  log "Output did not advance after producer startup."
  return 1
}

reset_watchdog_baselines() {
  local now frame

  now=$(date +%s)
  frame="$(normalize_number "$(progress_value "$OUT_PROGRESS" frame)")"

  OUT_LAST_FRAME="$frame"
  OUT_LAST_ADVANCE_AT="$now"
  GRACE_UNTIL=$((now + 5))
}

start_producer_standby() {
  local baseline

  stop_producer
  sleep 1

  : > "$PROD_LOG"
  : > "$STREAMLINK_LOG"

  baseline="$(normalize_number "$(progress_value "$OUT_PROGRESS" frame)")"

  log "Starting standby producer..."

  setsid ffmpeg -y -hide_banner -loglevel warning -nostdin \
    -re -stream_loop -1 -i "$STANDBY_TS" \
    -map 0:v:0 -map 0:a:0 \
    -c copy \
    -mpegts_flags +resend_headers+initial_discontinuity \
    -f mpegts "$FIFO" \
    >/dev/null 2>"$PROD_LOG" &

  PROD=$!

  if ! wait_for_output_advance "$baseline" 35; then
    show_producer_diagnostics
    stop_producer
    return 1
  fi

  MODE="STANDBY"
  reset_watchdog_baselines

  log "Standby video is flowing through the output."
  return 0
}

start_producer_live() {
  local baseline

  stop_producer
  sleep 0.3

  : > "$PROD_LOG"
  : > "$STREAMLINK_LOG"

  baseline="$(normalize_number "$(progress_value "$OUT_PROGRESS" frame)")"

  log "Starting direct Kick pass-through for ${STREAMER} (no video re-encode)..."

  export STREAMER UA KICK_URL FIFO STREAMLINK_LOG

  setsid bash -c '
    exec streamlink --stdout \
      --http-header "User-Agent=$UA" \
      "$KICK_URL" best \
      2>"$STREAMLINK_LOG" > "$FIFO"
  ' >/dev/null 2>&1 &

  PROD=$!

  if ! wait_for_output_advance "$baseline" 10; then
    show_producer_diagnostics
    stop_producer
    return 1
  fi

  MODE="LIVE"
  LIVE_FAILS=0
  reset_watchdog_baselines

  log "LIVE source packets are reaching the output (video copied as received)."
  return 0
}

is_live() {
  local result

  result="$(
    timeout --signal=TERM --kill-after=2s 8s \
      streamlink --stream-url \
      --http-header "User-Agent=$UA" \
      "$KICK_URL" best 2>/dev/null |
      head -n 1 || true
  )"

  [[ "$result" == http://* || "$result" == https://* ]]
}

start_best_source() {
  if is_live; then
    log "Kick reports ${STREAMER} LIVE; validating the media path..."

    if start_producer_live; then
      return 0
    fi

    log "LIVE startup did not pass the media checks; using standby."
  else
    log "Kick reports ${STREAMER} OFFLINE; using standby."
  fi

  start_producer_standby
}

switch_to_live() {
  log "Switching source: STANDBY -> LIVE."

  if start_producer_live; then
    return 0
  fi

  log "LIVE transition failed; restoring standby."
  start_producer_standby
}

switch_to_standby() {
  log "Switching source: LIVE -> STANDBY."

  LIVE_FAILS=0
  start_producer_standby
}

rebuild_output() {
  local attempt="$1"

  log "Rebuilding FIFO/output stack (attempt ${attempt})..."

  stop_producer
  stop_output
  stop_keeper

  setup_fifo || return 1
  start_output || return 1

  start_keeper || {
    stop_output
    return 1
  }

  start_best_source
}

recover_producer() {
  log "Producer health check failed; selecting a fresh source."

  stop_producer
  start_best_source
}

# -----------------------------
# Initialization
# -----------------------------

for command in ffmpeg ffprobe streamlink python3 setsid timeout; do
  command -v "$command" >/dev/null 2>&1 || {
    log "ERROR: Required command not found: $command"
    exit 1
  }
done

make_standby
setup_fifo
start_output
start_keeper

if ! start_best_source; then
  log "Initial source could not be started; trying one complete output rebuild."

  if ! rebuild_output 1; then
    log "ERROR: Initial relay startup failed."
    exit 1
  fi
fi

LAST_STATUS_CHECK=$(date +%s)
log "Relay initialized in ${MODE} mode."

# -----------------------------
# Supervisor loop
# -----------------------------

while true; do
  now=$(date +%s)

  # 1. Output process death.
  if ! is_pid_alive "$OUT"; then
    log "ERROR: Restream output process died."
    show_output_diagnostics

    rc=0
    wait "$OUT" || rc=$?
    log "Output FFmpeg exit code: $rc"

    OUT=""

    if ! rebuild_output 1; then
      sleep 5

      if ! rebuild_output 2; then
        log "ERROR: Output recovery failed twice; ending this run for GitHub Actions to restart on schedule."
        exit 1
      fi
    fi

    LAST_STATUS_CHECK=$(date +%s)
    continue
  fi

  # 2. Producer process death.
  if ! is_pid_alive "$PROD"; then
    log "Producer process is not alive."

    if ! recover_producer; then
      log "Producer recovery failed; rebuilding output stack."

      if ! rebuild_output 1; then
        sleep 5
        if ! rebuild_output 2; then
          exit 1
        fi
      fi
    fi

    continue
  fi

  # 3. Track actual output video-frame progress.
  out_frame="$(normalize_number "$(progress_value "$OUT_PROGRESS" frame)")"

  if (( out_frame > ${OUT_LAST_FRAME:-0} )); then
    OUT_LAST_FRAME="$out_frame"
    OUT_LAST_ADVANCE_AT="$now"
  fi

  if (( now >= GRACE_UNTIL )); then
    if (( now - OUT_LAST_ADVANCE_AT >= 5 )); then
      if [[ "$MODE" == "LIVE" ]]; then
        log "LIVE video stalled for 5 seconds; switching to standby."

        if ! switch_to_standby; then
          log "Could not start standby after LIVE stall; rebuilding output stack."

          if ! rebuild_output 1; then
            sleep 3
            if ! rebuild_output 2; then
              exit 1
            fi
          fi
        fi
      else
        log "Standby output has stalled for 5 seconds; rebuilding output stack."

        if ! rebuild_output 1; then
          sleep 3
          if ! rebuild_output 2; then
            exit 1
          fi
        fi
      fi

      LAST_STATUS_CHECK=$(date +%s)
      continue
    fi
  fi

  # 4. Check Kick status every 5 seconds.
  if (( now - LAST_STATUS_CHECK >= 5 )); then
    LAST_STATUS_CHECK="$now"

    if is_live; then
      if [[ "$MODE" == "STANDBY" ]]; then
        if ! switch_to_live; then
          log "LIVE switch did not validate; remaining in STANDBY."
        fi
      else
        LIVE_FAILS=0
      fi
    else
      if [[ "$MODE" == "LIVE" ]]; then
        LIVE_FAILS=$((LIVE_FAILS + 1))
        log "Kick status check failed (${LIVE_FAILS}/3)."

        if (( LIVE_FAILS >= 3 )); then
          if ! switch_to_standby; then
            log "Standby transition failed; rebuilding output stack."

            if ! rebuild_output 1; then
              sleep 5
              if ! rebuild_output 2; then
                exit 1
              fi
            fi
          fi
        fi
      fi
    fi
  fi

  sleep 1
done
