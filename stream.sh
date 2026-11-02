#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Ultimate Stability (Zero-CPU)
# ═══════════════════════════════════════════════════

STREAMER="SXB"
LOGO_URL="https://a.top4top.io/p_394102x460.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/standby_sxb"

mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  1. توليد شاشة الانتظار (مرة واحدة فقط)
# ═══════════════════════════════════════════════════
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 تجهيز شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")
LOGO_URL = os.environ.get("LOGO_URL")

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
draw_corner(40, 40, 1, 1)
draw_corner(W-40, 40, -1, 1)
draw_corner(40, H-40, 1, -1)
draw_corner(W-40, H-40, -1, -1)
bg = Image.alpha_composite(bg, corner)

font_sxb = load_font(FONT_EN, 150, 900)
sxb_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sxd = ImageDraw.Draw(sxb_img)
sxd.text((W//2, H//2), STREAMER, font=font_sxb, fill=(255, 0, 0, 255), anchor="mm")
sxb_glow = sxb_img.filter(ImageFilter.GaussianBlur(40))
bg = Image.alpha_composite(bg, sxb_glow)
bg = Image.alpha_composite(bg, sxb_img)

try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=10).read())).convert("RGBA")
    logo = logo.resize((150, int(logo.height * (150 / logo.width))), Image.LANCZOS)
    bg.alpha_composite(logo, ((W - 150)//2, H//2 - 200))
except Exception:
    pass

bg.convert("RGB").save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" LOGO_URL="$LOGO_URL" python3 /tmp/make_ui.py
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 30 -c:a aac -ar 44100 -ac 2 -shortest -f mpegts "$WORKDIR/standby.ts"
fi

# ═══════════════════════════════════════════════════
#  2. إعداد الأنبوب
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM -- -"$PROD" 2>/dev/null
    pkill -f streamlink 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  3. المخرج (OUT) - 0% معالج
# ═══════════════════════════════════════════════════
start_output() {
    ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 \
        -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -f mpegts -i "$FIFO" -map 0:v:0 -map 0:a:0? -c:v copy -c:a copy \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize -rtmp_live live \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 3
}

# ═══════════════════════════════════════════════════
#  4. منتج الشاشة
# ═══════════════════════════════════════════════════
start_producer_standby() {
    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  5. منتج البث
# ═══════════════════════════════════════════════════
start_producer_live() {
    setsid bash -c "streamlink --http-header 'User-Agent=$UA' 'https://kick.com/$STREAMER' best --stdout 2>/dev/null | \
        ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -i pipe:0 -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -f mpegts '$FIFO' >/tmp/prod.log 2>&1" &
    PROD=$!
}

kill_producer() {
    if [ -n "$PROD" ]; then 
        kill -TERM -- -"$PROD" 2>/dev/null
        sleep 0.5 
        kill -9 -- -"$PROD" 2>/dev/null
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  6. التشغيل
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 2
start_output

MODE="STANDBY"

while true; do
    if ! kill -0 "$OUT" 2>/dev/null; then
        start_output
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        start_producer_standby
        MODE="STANDBY"
        sleep 2
        continue
    fi

    if [ "$MODE" = "STANDBY" ]; then
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then
            echo "🎯 شونق بدأ البث!"
            kill_producer; sleep 0.5
            start_producer_live
            sleep 2
            if kill -0 "$PROD" 2>/dev/null; then 
                MODE="LIVE"; echo "🔴 مباشر: SXB"
            else 
                start_producer_standby; MODE="STANDBY"
            fi
        fi
    fi

    # إذا كنا في وضع البث، ننتظر 15 ثانية عشان ما نطقطق ونسبب انهيار
    # الكود اللي فوق يفحص إذا مات المنتج، ويرجع للانتظار تلقائياً
    if [ "$MODE" = "LIVE" ]; then
        sleep 15
    else
        sleep 15
    fi
done
