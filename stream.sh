#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — V10 (Persistent FIFO + Watchdog)
# ═══════════════════════════════════════════════════

STREAMER="SXB"
TITLE_AR="توقف البث من شونق"
SUBTITLE_AR="بث شونق سابثون 30 يوم!"
LOGO_URL="https://a.top4top.io/p_394102x460.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ⚠️ المفتاح المباشر (Hardcoded)
RESTREAM_KEY="${RESTREAM_KEY:-re_12552561_event81737fba9ada4713ab13ad7e04a36880}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/standby_sxb"
mkdir -p "$WORKDIR"

# 1. توليد شاشة الانتظار (1080p 60FPS)
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 تصميم شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")
TITLE = os.environ.get("TITLE_AR", "توقف البث")
SUBTITLE = os.environ.get("SUBTITLE_AR", "جاري الانتظار...")
STREAMER = os.environ.get("STREAMER", "SXB")
LOGO_URL = os.environ.get("LOGO_URL", "")

def load_font(path, size, weight=700):
    try:
        font = ImageFont.truetype(path, size)
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        return font
    except: return ImageFont.load_default()

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(30*(1-t)), int(0), int(0)))

glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 600, H//2 - 400, W//2 + 600, H//2 + 400], fill=(255, 0, 0, 80))
glow = glow.filter(ImageFilter.GaussianBlur(250))
bg = bg.convert("RGBA")
bg = Image.alpha_composite(bg, glow)

corner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(corner)
SIZE = 80
def draw_corner(cx, cy, fx, fy):
    cd.line([(cx, cy), (cx + SIZE*fx, cy)], fill=(255, 0, 0, 255), width=4)
    cd.line([(cx, cy), (cx, cy + SIZE*fy)], fill=(255, 0, 0, 255), width=4)
draw_corner(40, 40, 1, 1); draw_corner(W-40, 40, -1, 1)
draw_corner(40, H-40, 1, -1); draw_corner(W-40, H-40, -1, -1)
bg = Image.alpha_composite(bg, corner)

card_w, card_h = 1200, 600
card_x, card_y = (W - card_w)//2, (H - card_h)//2
card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
cd.rounded_rectangle([(card_x, card_y), (card_x+card_w, card_y+card_h)], radius=20, fill=(20, 0, 0, 150), outline=(255, 0, 0, 100), width=2)
cd.rounded_rectangle([(card_x+5, card_y+5), (card_x+card_w-5, card_y+card_h-5)], radius=18, outline=(255, 255, 255, 30), width=1)
bg = Image.alpha_composite(bg, card)

font_title = load_font(FONT_AR, 100, 900)
font_sub = load_font(FONT_AR, 50, 700)
font_sxb = load_font(FONT_EN, 150, 900)

t_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(t_img).text((W//2, card_y + 100), TITLE, font=font_title, fill=(255, 255, 255, 255), anchor="mm", direction="rtl")
bg = Image.alpha_composite(bg, t_img.filter(ImageFilter.GaussianBlur(20)))
bg = Image.alpha_composite(bg, t_img)

s_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(s_img).text((W//2, card_y + 220), SUBTITLE, font=font_sub, fill=(255, 255, 255, 200), anchor="mm", direction="rtl")
bg = Image.alpha_composite(bg, s_img)

sxb_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sxb_img).text((W//2, card_y + 400), STREAMER, font=font_sxb, fill=(255, 0, 0, 255), anchor="mm")
bg = Image.alpha_composite(bg, sxb_img.filter(ImageFilter.GaussianBlur(40)))
bg = Image.alpha_composite(bg, sxb_img)

try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=10).read())).convert("RGBA")
    logo = logo.resize((150, int(logo.height * (150 / logo.width))), Image.LANCZOS)
    bg.alpha_composite(logo, ((W - 150)//2, card_y - 90))
except Exception: pass

bg.convert("RGB").save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" STREAMER="$STREAMER" TITLE_AR="$TITLE_AR" SUBTITLE_AR="$SUBTITLE_AR" LOGO_URL="$LOGO_URL" python3 /tmp/make_ui.py
    echo "🎬 ترميز شاشة الانتظار..."
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 60 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 120 -r 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -mpegts_flags +resend_headers \
        -f mpegts "$WORKDIR/standby.ts"
fi

# ==========================================================
# SXB Broadcast V10 - Persistent FIFO Architecture
# ==========================================================

set -uo pipefail

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"

FIFO="/tmp/relay.ts"
WORKDIR="/tmp/standby_sxb"

OUT=""
PROD=""
KEEPER=""

MODE="STANDBY"
LIVE_FAILS=0
LAST_CHECK=0

OUT_STARTED=0
PROD_STARTED=0

OUT_PREV_FRAME=""
PROD_PREV_FRAME=""

OUT_STALL=0
PROD_STALL=0

KEEPER_READY="/tmp/relay_keeper.ready"

export STREAMER UA FIFO WORKDIR

# ----------------------------------------------------------
# Process management
# ----------------------------------------------------------

stop_group() {
    local pid="${1:-}"
    local i=0

    [ -n "$pid" ] || return 0

    kill -TERM -- "-$pid" 2>/dev/null || true

    while [ "$i" -lt 20 ]; do
        if ! kill -0 -- "-$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            return 0
        fi

        sleep 0.2
        i=$((i + 1))
    done

    kill -KILL -- "-$pid" 2>/dev/null || true

    i=0
    while [ "$i" -lt 30 ]; do
        if ! kill -0 -- "-$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            return 0
        fi

        sleep 0.2
        i=$((i + 1))
    done

    wait "$pid" 2>/dev/null || true

    if kill -0 -- "-$pid" 2>/dev/null; then
        echo "ERROR: Process group $pid still exists"
        return 1
    fi

    return 0
}

stop_producer() {
    [ -n "$PROD" ] || return 0

    local old="$PROD"

    if ! stop_group "$old"; then
        return 1
    fi

    PROD=""
    return 0
}

stop_keeper() {
    [ -n "$KEEPER" ] || return 0

    local old="$KEEPER"

    if ! stop_group "$old"; then
        return 1
    fi

    KEEPER=""
    return 0
}

stop_output() {
    [ -n "$OUT" ] || return 0

    local old="$OUT"
    local i=0

    kill -TERM "$old" 2>/dev/null || true

    while [ "$i" -lt 20 ]; do
        if ! kill -0 "$old" 2>/dev/null; then
            wait "$old" 2>/dev/null || true
            OUT=""
            return 0
        fi

        sleep 0.2
        i=$((i + 1))
    done

    kill -KILL "$old" 2>/dev/null || true
    wait "$old" 2>/dev/null || true

    if kill -0 "$old" 2>/dev/null; then
        echo "ERROR: Output process did not stop"
        return 1
    fi

    OUT=""
    return 0
}

cleanup() {
    trap - EXIT INT TERM

    echo "Cleaning up..."

    stop_producer || true
    stop_output || true
    stop_keeper || true

    rm -f "$KEEPER_READY"
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# ----------------------------------------------------------
# FIFO
# ----------------------------------------------------------

setup_fifo() {
    rm -f "$FIFO" "$KEEPER_READY"

    if ! mkfifo "$FIFO"; then
        echo "ERROR: Cannot create FIFO"
        return 1
    fi
}

# ----------------------------------------------------------
# Persistent writer
# ----------------------------------------------------------

start_keeper() {
    rm -f "$KEEPER_READY"

    setsid bash -c '
        exec 3>"$1" || exit 1
        : > "$2"
        exec sleep infinity
    ' _ "$FIFO" "$KEEPER_READY" >/tmp/keeper.log 2>&1 &

    KEEPER=$!

    local i=0

    while [ "$i" -lt 100 ]; do
        if [ -f "$KEEPER_READY" ]; then
            if ! kill -0 "$OUT" 2>/dev/null; then
                echo "ERROR: Output died during FIFO initialization"
                stop_keeper || true
                return 1
            fi

            return 0
        fi

        if ! kill -0 "$OUT" 2>/dev/null; then
            echo "ERROR: Output failed to open FIFO"
            stop_keeper || true
            return 1
        fi

        sleep 0.1
        i=$((i + 1))
    done

    echo "ERROR: FIFO writer initialization timed out"
    stop_keeper || true
    return 1
}

# ----------------------------------------------------------
# Output
# ----------------------------------------------------------

start_output() {
    rm -f /tmp/out.prog

    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+discardcorrupt \
        -f mpegts -i "$FIFO" \
        -map 0:v:0 -map 0:a:0? \
        -c:v copy -c:a copy \
        -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -rtmp_live live \
        -progress /tmp/out.prog \
        -stats_period 1 \
        -f flv "$RESTREAM_URL" \
        >/tmp/out.log 2>&1 &

    OUT=$!
    OUT_STARTED=$(date +%s)
    OUT_PREV_FRAME=""
    OUT_STALL=0
}

# ----------------------------------------------------------
# Producer progress
# ----------------------------------------------------------

get_frame() {
    local file="$1"

    [ -f "$file" ] || return 0

    tail -n 30 "$file" 2>/dev/null |
        awk -F= '$1=="frame" {v=$2} END {print v}'
}

wait_producer_ready() {
    local i=0
    local frame=""

    while [ "$i" -lt 20 ]; do
        if ! kill -0 "$PROD" 2>/dev/null; then
            echo "Producer process exited"
            return 1
        fi

        frame=$(get_frame /tmp/prod.prog)

        if [[ "$frame" =~ ^[0-9]+$ ]] && [ "$frame" -gt 0 ]; then
            return 0
        fi

        sleep 1
        i=$((i + 1))
    done

    echo "Producer did not deliver video frames in time"
    return 1
}

# ----------------------------------------------------------
# Standby producer
# ----------------------------------------------------------

start_producer_standby() {
    rm -f /tmp/prod.prog

    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -re -stream_loop -1 \
        -i "$WORKDIR/standby.ts" \
        -c copy \
        -mpegts_flags +resend_headers \
        -progress /tmp/prod.prog \
        -stats_period 1 \
        -f mpegts "$FIFO" \
        >/tmp/prod.log 2>&1 &

    PROD=$!
    PROD_STARTED=$(date +%s)
    PROD_PREV_FRAME=""
    PROD_STALL=0

    if wait_producer_ready; then
        MODE="STANDBY"
        echo "STANDBY producer ready"
        return 0
    fi

    stop_producer || return 1
    return 1
}

# ----------------------------------------------------------
# LIVE producer
# ----------------------------------------------------------

start_producer_live() {
    rm -f /tmp/prod.prog

    setsid bash -o pipefail -c '
        streamlink \
            --http-header "User-Agent=$UA" \
            "https://kick.com/$STREAMER" \
            best --stdout 2>/tmp/sl_err.log |
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -thread_queue_size 512 \
            -fflags +genpts+discardcorrupt \
            -i pipe:0 \
            -c:v copy \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -mpegts_flags +resend_headers \
            -progress /tmp/prod.prog \
            -stats_period 1 \
            -f mpegts "$FIFO" \
            >/tmp/prod.log 2>&1
    ' >/dev/null 2>&1 &

    PROD=$!
    PROD_STARTED=$(date +%s)
    PROD_PREV_FRAME=""
    PROD_STALL=0

    if wait_producer_ready; then
        MODE="LIVE"
        LIVE_FAILS=0
        echo "LIVE producer ready"
        return 0
    fi

    stop_producer || return 1
    return 1
}

# ----------------------------------------------------------
# Kick status
# ----------------------------------------------------------

is_live() {
    local url=""

    url=$(
        timeout 6 streamlink \
            --http-header "User-Agent=$UA" \
            "https://kick.com/$STREAMER" \
            best --stream-url 2>/dev/null |
        grep -m1 '^http' || true
    )

    [ -n "$url" ]
}

# ----------------------------------------------------------
# Select source
# ----------------------------------------------------------

start_best_source() {
    if is_live; then
        echo "Kick reports LIVE"

        if start_producer_live; then
            return 0
        fi

        echo "LIVE startup failed; falling back to standby"
    fi

    start_producer_standby
}

switch_to_live() {
    echo "Switching to LIVE..."

    if ! stop_producer; then
        echo "ERROR: Could not stop previous producer"
        return 1
    fi

    if start_producer_live; then
        LIVE_FAILS=0
        return 0
    fi

    echo "LIVE failed; switching to standby"

    start_producer_standby
}

switch_to_standby() {
    echo "Switching to STANDBY..."

    if ! stop_producer; then
        echo "ERROR: Could not stop previous producer"
        return 1
    fi

    LIVE_FAILS=0
    start_producer_standby
}

# ----------------------------------------------------------
# Full output restart
# ----------------------------------------------------------

restart_all() {
    echo "Restarting complete relay..."

    if ! stop_producer; then return 1; fi
    if ! stop_output; then return 1; fi
    if ! stop_keeper; then return 1; fi

    if ! setup_fifo; then return 1; fi

    start_output

    if ! start_keeper; then
        stop_output || true
        return 1
    fi

    if ! start_best_source; then
        echo "ERROR: Could not start any producer"
        return 1
    fi

    OUT_PREV_FRAME=""
    OUT_STALL=0

    echo "Relay restarted successfully"
    return 0
}

# ----------------------------------------------------------
# Initialization
# ----------------------------------------------------------

echo "Starting SXB relay..."

if ! setup_fifo; then
    exit 1
fi

start_output

if ! start_keeper; then
    exit 1
fi

if ! start_best_source; then
    echo "ERROR: Initial producer startup failed"
    exit 1
fi

LAST_CHECK=$(date +%s)

# ----------------------------------------------------------
# Main watchdog loop
# ----------------------------------------------------------

while true; do
    NOW=$(date +%s)

    # 1. Output process death
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "Output process died"

        if ! restart_all; then
            echo "ERROR: Full restart failed"
            exit 1
        fi

        LAST_CHECK=$(date +%s)
        continue
    fi

    # 2. Producer process death
    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "Producer process died"

        if ! stop_producer; then
            exit 1
        fi

        if ! start_best_source; then
            echo "ERROR: Producer recovery failed"
            exit 1
        fi

        continue
    fi

    # 3. Output video-frame watchdog
    if [ $((NOW - OUT_STARTED)) -ge 20 ]; then
        OUT_FRAME=$(get_frame /tmp/out.prog)
        OUT_MTIME=$(stat -c %Y /tmp/out.prog 2>/dev/null || echo 0)
        OUT_AGE=$((NOW - OUT_MTIME))

        if [ "$OUT_AGE" -ge 15 ]; then
            OUT_STALL=12
        elif [[ "$OUT_FRAME" =~ ^[0-9]+$ ]]; then
            if [ -n "$OUT_PREV_FRAME" ] &&
               [ "$OUT_FRAME" -le "$OUT_PREV_FRAME" ]; then
                OUT_STALL=$((OUT_STALL + 1))
            else
                OUT_STALL=0
            fi

            OUT_PREV_FRAME="$OUT_FRAME"
        else
            OUT_STALL=$((OUT_STALL + 1))
        fi

        if [ "$OUT_STALL" -ge 12 ]; then
            echo "Output video progress stalled"

            if ! restart_all; then
                echo "ERROR: Output recovery failed"
                exit 1
            fi

            LAST_CHECK=$(date +%s)
            continue
        fi
    fi

    # 4. Producer video-frame watchdog
    if [ $((NOW - PROD_STARTED)) -ge 20 ]; then
        PROD_FRAME=$(get_frame /tmp/prod.prog)
        PROD_MTIME=$(stat -c %Y /tmp/prod.prog 2>/dev/null || echo 0)
        PROD_AGE=$((NOW - PROD_MTIME))

        if [ "$PROD_AGE" -ge 15 ]; then
            PROD_STALL=12
        elif [[ "$PROD_FRAME" =~ ^[0-9]+$ ]]; then
            if [ -n "$PROD_PREV_FRAME" ] &&
               [ "$PROD_FRAME" -le "$PROD_PREV_FRAME" ]; then
                PROD_STALL=$((PROD_STALL + 1))
            else
                PROD_STALL=0
            fi

            PROD_PREV_FRAME="$PROD_FRAME"
        else
            PROD_STALL=$((PROD_STALL + 1))
        fi

        if [ "$PROD_STALL" -ge 12 ]; then
            echo "Producer video progress stalled"

            if ! stop_producer; then
                exit 1
            fi

            if ! start_best_source; then
                echo "ERROR: Producer recovery failed"
                exit 1
            fi

            continue
        fi
    fi

    # 5. Kick status every 10 seconds
    if [ $((NOW - LAST_CHECK)) -ge 10 ]; then
        LAST_CHECK=$NOW

        if is_live; then
            if [ "$MODE" = "STANDBY" ]; then
                echo "Kick streamer is LIVE"

                if ! switch_to_live; then
                    echo "ERROR: LIVE transition failed"
                    exit 1
                fi
            else
                LIVE_FAILS=0
            fi
        else
            if [ "$MODE" = "LIVE" ]; then
                LIVE_FAILS=$((LIVE_FAILS + 1))
                echo "Kick check failed: $LIVE_FAILS/3"

                if [ "$LIVE_FAILS" -ge 3 ]; then
                    if ! switch_to_standby; then
                        echo "ERROR: STANDBY transition failed"
                        exit 1
                    fi
                fi
            fi
        fi
    fi

    sleep 1
done
