#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Claude & ChatGPT Approved (Zero-CPU)
# ═══════════════════════════════════════════════════

STREAMER="SXB"
TITLE_AR="توقف البث من شونق"
SUBTITLE_AR="بث شونق سابثون 30 يوم!"
LOGO_URL="https://a.top4top.io/p_394102x460.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/standby_sxb"
mkdir -p "$WORKDIR"

# 1. توليد شاشة الانتظار (1080p 60FPS لتطابق بث شونق)
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
    echo "🎬 ترميز شاشة الانتظار (60FPS)..."
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 60 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 120 -r 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -mpegts_flags +resend_headers \
        -f mpegts "$WORKDIR/standby.ts"
fi

# ═══════════════════════════════════════════════════
#  2. إعداد الأنبوب (بدون exec 3<> القاتل)
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
# كاتب وهمي يبقي الأنبوب مفتوحاً للمخرج (يمنع التعليق)
sleep 999999 > "$FIFO" &
DUMMY_WRITER=$!

cleanup() {
    echo "🧹 تنظيف..."
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM -- -"$PROD" 2>/dev/null
    kill -TERM "$DUMMY_WRITER" 2>/dev/null
    pkill -f streamlink 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  3. المخرج (OUT) - Zero CPU مع منع التراكم
# ═══════════════════════════════════════════════════
start_output() {
    ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 512 \
        -re -fflags +genpts+discardcorrupt -err_detect ignore_err \
        -f mpegts -i "$FIFO" -map 0:v:0 -map 0:a:0? -c:v copy -c:a copy \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize -rtmp_live live \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 2
}

# ═══════════════════════════════════════════════════
#  4. منتج الشاشة (Standby)
# ═══════════════════════════════════════════════════
start_producer_standby() {
    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -mpegts_flags +resend_headers -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  5. منتج البث (Live)
# ═══════════════════════════════════════════════════
start_producer_live() {
    setsid bash -c "streamlink --http-header 'User-Agent=$UA' 'https://kick.com/$STREAMER' best --stdout 2>/tmp/streamlink_err.log | \
        ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 512 -fflags +genpts+discardcorrupt -err_detect ignore_err \
        -i pipe:0 -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -mpegts_flags +resend_headers -f mpegts '$FIFO' >/tmp/prod.log 2>&1" &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  6. قتل المنتج (القتل الرحيم SIGINT)
# ═══════════════════════════════════════════════════
kill_producer() {
    if [ -n "$PROD" ]; then 
        kill -2 -- -"$PROD" 2>/dev/null
        for _ in {1..10}; do
            if ! kill -0 -- -"$PROD" 2>/dev/null; then break; fi
            sleep 0.2
        done
        kill -9 -- -"$PROD" 2>/dev/null
        wait "$PROD" 2>/dev/null
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  7. التشغيل الرئيسي (استجابة فورية)
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 2
start_output

MODE="STANDBY"

while true; do
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer; sleep 1; start_output; sleep 1; continue
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة..."
        start_producer_standby
        MODE="STANDBY"
        continue
    fi

    if [ "$MODE" = "STANDBY" ]; then
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then
            echo "🎯 شونق بدأ البث! (تحويل فوري...)"
            kill_producer
            start_producer_live
            sleep 2
            if kill -0 "$PROD" 2>/dev/null; then 
                MODE="LIVE"; echo "🔴 مباشر: SXB"
            else 
                start_producer_standby; MODE="STANDBY"
            fi
        fi
    fi

    # استجابة فورية (تسمح للـ Trap بالعمل فوراً)
    sleep 1 & wait $!
done
