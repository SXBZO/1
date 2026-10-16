#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Kick → Restream
#  مع شاشة انتظار احترافية
# ═══════════════════════════════════════════════════

# ─── الإعدادات ───
STREAMER="SXB"
TITLE_AR="توقف البث من شونق"
SUBTITLE_AR="بث شونق سابثون 30 يوم!"
STREAMER_LABEL="SXB"

COLOR_TITLE="#ff7700"
COLOR_SUB="#ffffff"
COLOR_STREAMER="#ffb366"
BG_TOP_R=10; BG_TOP_G=5;  BG_TOP_B=20
BG_BOT_R=25; BG_BOT_G=8;  BG_BOT_B=15
GLOW_R=255;  GLOW_G=120;  GLOW_B=20

FONT_SIZE_TITLE=110
FONT_SIZE_SUB=60
FONT_SIZE_STREAMER=44

Y_TITLE=280
Y_SUB=430
Y_STREAMER=540

LOGO_URL="https://a.top4top.io/p_394102x460.png"
LOGO_W=180
LOGO_BOTTOM=60
LOGO_SHOW=5
LOGO_CYCLE=7

FPS=60
GOP=120

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
# ═══════════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

# ─── الخطوط ───
FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
[ -z "$FONT_AR" ] && { echo "❌ لا يوجد خط عربي"; exit 1; }

FONT_EN="$HOME/.fonts/Orbitron-var.ttf"
[ ! -s "$FONT_EN" ] && { echo "❌ لا يوجد Orbitron"; exit 1; }

echo "🔤 الخطوط: عربي=$FONT_AR | إنجليزي=$FONT_EN"
echo "🎬 القناة: $STREAMER"

# ═══════════════════════════════════════════════════
#  توليد صورة شاشة الانتظار
# ═══════════════════════════════════════════════════
cat > /tmp/make_standby.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io

W, H = 1920, 1080
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE_AR"
SUBTITLE = "$SUBTITLE_AR"
STREAMER_LABEL = "$STREAMER_LABEL"
C_TITLE = "$COLOR_TITLE"
C_SUB = "$COLOR_SUB"
C_STREAMER = "$COLOR_STREAMER"
FS_TITLE = $FONT_SIZE_TITLE
FS_SUB = $FONT_SIZE_SUB
FS_STREAMER = $FONT_SIZE_STREAMER
Y_TITLE = $Y_TITLE
Y_SUB = $Y_SUB
Y_STREAMER = $Y_STREAMER
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)
GLOW = ($GLOW_R, $GLOW_G, $GLOW_B, 70)
LOGO_URL = "$LOGO_URL"
LOGO_W = $LOGO_W
LOGO_BOTTOM = $LOGO_BOTTOM

# ─── تحميل الخط مع الأوزان ───
def load_font(path, size, weight=700):
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        if len(axes) == 1:
            font.set_variation_by_axes([weight])
        elif len(axes) == 2:
            font.set_variation_by_axes([0, weight])
        elif len(axes) == 3:
            font.set_variation_by_axes([0, weight, 0])
    except Exception:
        pass
    return font

# ─── 1) الخلفية المتدرجة ───
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))

bg = bg.convert("RGBA")

# ─── 2) توهج مركزي ───
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 800, H//2 - 600, W//2 + 800, H//2 + 600], fill=GLOW)
glow = glow.filter(ImageFilter.GaussianBlur(300))
bg = Image.alpha_composite(bg, glow)

# ─── 3) نمط ماس أسفل ───
pattern = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pd = ImageDraw.Draw(pattern)
size = 80
start_y = H - 280
row = 0
y = start_y
while y < H + size:
    x = (size // 2) if row % 2 else 0
    while x < W + size:
        pts = [(x, y - size//2), (x + size//2, y), (x, y + size//2), (x - size//2, y)]
        pd.polygon(pts, outline=(0, 0, 0, 200), width=2)
        x += size
    y += size // 2
    row += 1

mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
for yy in range(start_y, H):
    a = min(255, int((yy - start_y) / 0.7))
    md.line([(0, yy), (W, yy)], fill=a)
pattern.putalpha(mask)
bg = Image.alpha_composite(bg, pattern)

# ─── 4) طبقة النصوص مع توهج ───
texts = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(texts)

def draw_glow_text(text, font, color, cx, cy, align="center"):
    """رسم نص مع توهج ثلاثي الطبقات وحد أسود"""
    # تحويل اللون
    c = color.lstrip("#")
    r, g, b = tuple(int(c[i:i+2], 16) for i in (0, 2, 4))

    bbox = td.textbbox((0, 0), text, font=font, direction="rtl")
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    if align == "center":
        x = cx - tw // 2 - bbox[0]
    elif align == "right":
        x = cx - tw - bbox[0]
    else:
        x = cx - bbox[0]
    y = cy - bbox[1]

    # توهج (3 طبقات)
    scale = font.size / 100
    for radius, alpha in [(int(40*scale), 80), (int(25*scale), 140), (int(12*scale), 200)]:
        temp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        tdd = ImageDraw.Draw(temp)
        tdd.text((x, y), text, font=font, fill=(r, g, b, alpha), direction="rtl")
        temp = temp.filter(ImageFilter.GaussianBlur(radius))
        texts.alpha_composite(temp)

    # حد أسود
    outline_w = max(3, int(font.size / 25))
    for dx in range(-outline_w, outline_w + 1):
        for dy in range(-outline_w, outline_w + 1):
            if dx*dx + dy*dy <= outline_w*outline_w:
                td.text((x+dx, y+dy), text, font=font, fill=(0, 0, 0, 255), direction="rtl")

    # النص الأساسي
    td.text((x, y), text, font=font, fill=(r, g, b, 255), direction="rtl")

# العنوان الرئيسي
font_title = load_font(FONT_AR, FS_TITLE, 900)
draw_glow_text(TITLE, font_title, C_TITLE, W//2, Y_TITLE)

# السطر الثاني
font_sub = load_font(FONT_AR, FS_SUB, 700)
draw_glow_text(SUBTITLE, font_sub, C_SUB, W//2, Y_SUB)

# اسم القناة (بالإنجليزية)
font_str = load_font(FONT_EN, FS_STREAMER, 700)
# Orbitron خط إنجليزي — نستخدم ltr
c = C_STREAMER.lstrip("#")
r, g, b = tuple(int(c[i:i+2], 16) for i in (0, 2, 4))
bbox = td.textbbox((0, 0), STREAMER_LABEL, font=font_str)
tw = bbox[2] - bbox[0]
x = W//2 - tw//2 - bbox[0]
y = Y_STREAMER - bbox[1]
# توهج
for radius, alpha in [(30, 80), (18, 140), (8, 200)]:
    temp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tdd = ImageDraw.Draw(temp)
    tdd.text((x, y), STREAMER_LABEL, font=font_str, fill=(r, g, b, alpha))
    temp = temp.filter(ImageFilter.GaussianBlur(radius))
    texts.alpha_composite(temp)
# حد
outline_w = 3
for dx in range(-outline_w, outline_w + 1):
    for dy in range(-outline_w, outline_w + 1):
        if dx*dx + dy*dy <= outline_w*outline_w:
            td.text((x+dx, y+dy), STREAMER_LABEL, font=font_str, fill=(0, 0, 0, 255))
td.text((x, y), STREAMER_LABEL, font=font_str, fill=(r, g, b, 255))

bg = Image.alpha_composite(bg, texts)

# ─── 5) الشعار (خلفية شفافة، مدموج) ───
try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo_data = urllib.request.urlopen(req, timeout=25).read()
    logo = Image.open(io.BytesIO(logo_data)).convert("RGBA")
    # تصغير مع الحفاظ على النسبة
    ratio = LOGO_W / logo.width
    logo = logo.resize((LOGO_W, int(logo.height * ratio)), Image.LANCZOS)
    # موضع أسفل الوسط
    lx = (W - logo.width) // 2
    ly = H - logo.height - LOGO_BOTTOM
    # دمج الشعار مع الحفاظ على الشفافية
    bg.alpha_composite(logo, (lx, ly))
    print(f"✅ الشعار مدموج: {logo.width}x{logo.height}")
except Exception as e:
    print(f"⚠️ فشل الشعار: {e}")

# ─── حفظ ───
bg.convert("RGB").save("/tmp/standby.png", "PNG", optimize=True)
print("✅ standby.png جاهز")
PYEOF

echo "🎨 توليد شاشة الانتظار..."
python3 /tmp/make_standby.py
[ ! -s /tmp/standby.png ] && { echo "❌ فشل التوليد"; exit 1; }

# ═══════════════════════════════════════════════════
#  FIFO
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═══════════════════════════════════════════════════
#  منتج شاشة الانتظار
# ═══════════════════════════════════════════════════
start_producer_standby() {
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -loop 1 -framerate $FPS -i /tmp/standby.png \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -map 0:v:0 -map 1:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
        -r $FPS -g $GOP \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  منتج البث المباشر
# ═══════════════════════════════════════════════════
start_producer_live() {
    local M3U8="$1"
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -headers "User-Agent: $UA" \
        -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
        -reconnect_delay_max 5 \
        -analyzeduration 2000000 -probesize 2000000 \
        -fflags +genpts+igndts \
        -i "$M3U8" \
        -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -muxdelay 0.1 -muxpreload 0.1 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  المخرج (يعيد ترميز لمنع انهيار mpegts)
# ═══════════════════════════════════════════════════
start_output() {
    echo "🔗 الاتصال بـ Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -f mpegts -i "$FIFO" \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -g $GOP -r $FPS \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 6
    if ! kill -0 $OUT 2>/dev/null; then
        echo "❌ فشل المخرج:"; tail -n 10 /tmp/out.log
        return 1
    fi
    echo "✅ المخرج شغال (PID: $OUT)"
    return 0
}

kill_producer() {
    [ -n "$PROD" ] && kill -9 "$PROD" 2>/dev/null
    [ -n "$PROD" ] && wait "$PROD" 2>/dev/null
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل الرئيسي
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."

start_producer_standby
sleep 5
kill -0 "$PROD" 2>/dev/null || { echo "❌ منتج الانتظار مات"; cat /tmp/prod.log; exit 1; }
echo "✅ شاشة الانتظار شغالة (PID: $PROD)"

start_output || exit 1

# إلغاء الرنات القديمة (خلفية)
( if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress \
          --json databaseId -q ".[].databaseId" 2>/dev/null | \
          awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do
        echo "🛑 إلغاء: $R"
        timeout 8 gh run cancel "$R" 2>/dev/null
    done
  fi ) >/tmp/cancel.log 2>&1 &

MODE="STANDBY"
TICK=0

# ═══════════════════════════════════════════════════
#  الحلقة الرئيسية — مراقبة SXB كل 15 ثانية
# ═══════════════════════════════════════════════════
while true; do
    # فحص حياة المخرج
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer
        sleep 2
        start_output || exit 1
        sleep 2
        continue
    fi

    # فحص حياة المنتج
    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة..."
        if [ "$MODE" = "LIVE" ]; then
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
                  --stream-timeout 15 "https://kick.com/$STREAMER" best \
                  --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then
                start_producer_live "$URL"
            else
                start_producer_standby
                MODE="STANDBY"
            fi
        else
            start_producer_standby
        fi
        sleep 3
        continue
    fi

    # فحص هل SXB يبث؟
    URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
          --stream-timeout 15 "https://kick.com/$STREAMER" best \
          --stream-url 2>/dev/null | grep -m1 "^http")

    if [ -n "$URL" ]; then
        # SXB يبث
        if [ "$MODE" != "LIVE" ]; then
            echo "🎯 SXB بدأ البث! التحويل..."
            kill_producer
            sleep 1
            start_producer_live "$URL"
            sleep 6
            if kill -0 "$PROD" 2>/dev/null; then
                MODE="LIVE"
                echo "✅ مباشر: SXB"
            else
                echo "⚠️ فشل تشغيل البث"
                MODE="NONE"
            fi
        fi
    else
        # SXB لا يبث
        if [ "$MODE" != "STANDBY" ]; then
            echo "⏳ SXB توقف — العودة لشاشة الانتظار"
            kill_producer
            sleep 1
            start_producer_standby
            sleep 3
            MODE="STANDBY"
        fi
    fi

    # DIAG كل دقيقة
    TICK=$((TICK + 1))
    if [ $((TICK % 4)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] الوضع=$MODE | المخرج=$OS | المنتج=$PS ──"
    fi

    sleep 15
done
