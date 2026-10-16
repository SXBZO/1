#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB — Kick → Restream (شاشة انتظار احترافية)
#  تصميم: أحمر / أبيض / أسود
# ═══════════════════════════════════════════════════

# ─── الإعدادات ───
STREAMER="SXB"
TITLE_AR="توقف البث من شونق"
SUBTITLE_AR="بث شونق سابثون 30 يوم!"
STREAMER_LABEL="SXB"
TOP_BAR_TEXT="SXB · LIVE STANDBY"

COLOR_TITLE="#ffffff"
COLOR_SUB="#ffffff"
COLOR_USER="#ffffff"
COLOR_RED="#ff0000"
BG_TOP_R=26; BG_TOP_G=0;  BG_TOP_B=0
BG_BOT_R=0;  BG_BOT_G=0;  BG_BOT_B=0
GLOW_R=255;  GLOW_G=0;    GLOW_B=0

FONT_SIZE_TITLE=110
FONT_SIZE_SUB=52
FONT_SIZE_USER=80
FONT_SIZE_BAR=18

Y_TITLE=340
Y_DIVIDER=430
Y_SUB=490
Y_USER=610

LOGO_URL="https://a.top4top.io/p_394102x460.png"
LOGO_W=170
LOGO_BOTTOM=70
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
WORKDIR="/tmp/standby_sxb"

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
#  توليد الصور
# ═══════════════════════════════════════════════════
mkdir -p "$WORKDIR"

cat > /tmp/make_sxb.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os, math

W, H = 1920, 1080
WORKDIR = "$WORKDIR"
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE_AR"
SUBTITLE = "$SUBTITLE_AR"
STREAMER = "$STREAMER_LABEL"
TOP_TEXT = "$TOP_BAR_TEXT"
C_TITLE = "$COLOR_TITLE"
C_SUB = "$COLOR_SUB"
C_USER = "$COLOR_USER"
C_RED = "$COLOR_RED"
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)
GLOW = ($GLOW_R, $GLOW_G, $GLOW_B, 65)
LOGO_URL = "$LOGO_URL"
LOGO_W = $LOGO_W
Y_TITLE = $Y_TITLE
Y_DIVIDER = $Y_DIVIDER
Y_SUB = $Y_SUB
Y_USER = $Y_USER

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

# ═══════════════════════════════════════════
#  الخلفية + النمط + Vignette + الزوايا + Top Bar
# ═══════════════════════════════════════════
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))
bg = bg.convert("RGBA")

# توهج مركزي
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 700, H//2 - 500, W//2 + 700, H//2 + 500], fill=GLOW)
glow = glow.filter(ImageFilter.GaussianBlur(280))
bg = Image.alpha_composite(bg, glow)

# نمط ماس أسفل
pattern = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pd = ImageDraw.Draw(pattern)
size = 70
start_y = H - 300
row = 0
y = start_y
while y < H + size:
    x = (size // 2) if row % 2 else 0
    while x < W + size:
        pts = [(x, y - size//2), (x + size//2, y), (x, y + size//2), (x - size//2, y)]
        pd.polygon(pts, outline=(255, 0, 0, 170), width=2)
        x += size
    y += size // 2
    row += 1
mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
for yy in range(start_y, H):
    a = min(200, int((yy - start_y) / 0.7))
    md.line([(0, yy), (W, yy)], fill=a)
pattern.putalpha(mask)
bg = Image.alpha_composite(bg, pattern)

# Vignette
vign = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vd = ImageDraw.Draw(vign)
for i in range(200):
    alpha = int(200 * (i / 200) ** 2)
    vd.ellipse([-i, -i, W + i, H + i], outline=(0, 0, 0, alpha), width=4)
bg = Image.alpha_composite(bg, vign)

# الزوايا (Corner ornaments)
corner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(corner)
SIZE = 70
INNER = 34
def draw_corner(cx, cy, flip_x=1, flip_y=1):
    x1 = cx
    y1 = cy
    x2 = cx + SIZE * flip_x
    y2 = cy + SIZE * flip_y
    cd.line([(x1, y1), (x2, y1)], fill=(255, 0, 0, 200), width=2)
    cd.line([(x1, y1), (x1, y2)], fill=(255, 0, 0, 200), width=2)
    # الداخلية
    ix1 = cx + 6 * flip_x
    iy1 = cy + 6 * flip_y
    ix2 = cx + (SIZE - 6) * flip_x
    iy2 = cy + (SIZE - 6) * flip_y
    cd.line([(ix1, iy1), (ix2, iy1)], fill=(255, 255, 255, 120), width=1)
    cd.line([(ix1, iy1), (ix1, iy2)], fill=(255, 255, 255, 120), width=1)

draw_corner(28, 28, 1, 1)        # TL
draw_corner(W - 28, 28, -1, 1)   # TR
draw_corner(28, H - 28, 1, -1)   # BL
draw_corner(W - 28, H - 28, -1, -1) # BR
bg = Image.alpha_composite(bg, corner)

bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")
print("✅ bg.png")

# ═══════════════════════════════════════════
#  Top Bar
# ═══════════════════════════════════════════
font_bar = load_font(FONT_EN, $FONT_SIZE_BAR, 700)

# قياس
tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
td = ImageDraw.Draw(tmp)
bb = td.textbbox((0, 0), TOP_TEXT, font=font_bar)
tw = bb[2] - bb[0]
th = bb[3] - bb[1]

bar_pad = 20
dot_size = 12
gap = 16
bar_w = tw + bar_pad * 2 + dot_size * 2 + gap * 4
bar_h = th + bar_pad * 2

bar = Image.new("RGBA", (bar_w, bar_h), (0, 0, 0, 0))
bd = ImageDraw.Draw(bar)

# الدائرة اليسرى
cx1 = bar_pad
cy_c = bar_h // 2
bd.ellipse([cx1, cy_c - dot_size//2, cx1 + dot_size, cy_c + dot_size//2], fill=(255, 0, 0, 255))

# النص
tx = bar_pad + dot_size + gap
bd.text((tx, cy_c - th//2 - bb[1]), TOP_TEXT, font=font_bar, fill=(255, 255, 255, 255))

# الدائرة اليمنى
cx2 = bar_w - bar_pad - dot_size
bd.ellipse([cx2, cy_c - dot_size//2, cx2 + dot_size, cy_c + dot_size//2], fill=(255, 0, 0, 255))

# توهج خفيف
bar_glow = Image.new("RGBA", (bar_w, bar_h), (0, 0, 0, 0))
bgd = ImageDraw.Draw(bar_glow)
bgd.ellipse([cx1 - 3, cy_c - dot_size//2 - 3, cx1 + dot_size + 3, cy_c + dot_size//2 + 3], fill=(255, 0, 0, 100))
bgd.ellipse([cx2 - 3, cy_c - dot_size//2 - 3, cx2 + dot_size + 3, cy_c + dot_size//2 + 3], fill=(255, 0, 0, 100))
bar_glow = bar_glow.filter(ImageFilter.GaussianBlur(6))
bar = Image.alpha_composite(bar_glow, bar)

bar.save(f"{WORKDIR}/topbar.png", "PNG")
print(f"✅ topbar.png {bar.size}")

# ═══════════════════════════════════════════
#  دالة رسم نص مع توهج أحمر
# ═══════════════════════════════════════════
def make_text_png(text, font, color, out, glow_color=(255, 0, 0), direction="rtl", glow_layers=None):
    if glow_layers is None:
        glow_layers = [(50, 70), (32, 120), (15, 180)]

    c = color.lstrip("#")
    r, g, b = tuple(int(c[i:i+2], 16) for i in (0, 2, 4))

    tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    bbox = td.textbbox((0, 0), text, font=font, direction=direction)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    pad = 100
    Wn = tw + pad * 2
    Hn = th + pad * 2

    glow_layer = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
    gx = pad - bbox[0]
    gy = pad - bbox[1]
    for radius, alpha in glow_layers:
        t = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
        tdd = ImageDraw.Draw(t)
        tdd.text((gx, gy), text, font=font, fill=glow_color + (alpha,), direction=direction)
        t = t.filter(ImageFilter.GaussianBlur(radius))
        glow_layer = Image.alpha_composite(glow_layer, t)

    outline = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
    od = ImageDraw.Draw(outline)
    ow = max(3, int(font.size / 22))
    for dx in range(-ow, ow + 1):
        for dy in range(-ow, ow + 1):
            if dx*dx + dy*dy <= ow*ow:
                od.text((gx+dx, gy+dy), text, font=font, fill=(0, 0, 0, 255), direction=direction)

    txt = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
    td2 = ImageDraw.Draw(txt)
    td2.text((gx, gy), text, font=font, fill=(r, g, b, 255), direction=direction)

    final = Image.alpha_composite(glow_layer, outline)
    final = Image.alpha_composite(final, txt)
    final.save(out, "PNG")
    print(f"✅ {os.path.basename(out)} {final.size}")

font_title = load_font(FONT_AR, $FONT_SIZE_TITLE, 900)
font_sub = load_font(FONT_AR, $FONT_SIZE_SUB, 700)
font_user = load_font(FONT_EN, $FONT_SIZE_USER, 900)

make_text_png(TITLE, font_title, C_TITLE, f"{WORKDIR}/title.png", glow_color=(255, 0, 0))
make_text_png(SUBTITLE, font_sub, C_SUB, f"{WORKDIR}/sub.png", glow_color=(255, 0, 0), glow_layers=[(40, 60), (25, 110), (12, 170)])
make_text_png(STREAMER, font_user, C_USER, f"{WORKDIR}/user.png", glow_color=(255, 0, 0), direction="ltr", glow_layers=[(55, 90), (35, 150), (18, 210)])

# ═══════════════════════════════════════════
#  Divider (خط + ◆)
# ═══════════════════════════════════════════
div_h = 60
div_w = int(W * 0.55)
div_img = Image.new("RGBA", (div_w, div_h), (0, 0, 0, 0))
dd = ImageDraw.Draw(div_img)

mid_y = div_h // 2

# الخط مع تلاشي في الأطراف
for i in range(div_w):
    t = i / div_w
    # منحنى: يزيد في الوسط ويقل في الأطراف
    alpha = int(200 * (1 - abs(t - 0.5) * 2) ** 1.5)
    dd.line([(i, mid_y), (i, mid_y + 1)], fill=(255, 0, 0, alpha))

# ◆ في الوسط
font_diamond = load_font(FONT_EN, 32, 700)
dd.text((div_w//2, mid_y), "◆", font=font_diamond, fill=(255, 0, 0, 255), anchor="mm")

# توهج حول ◆
glow_d = Image.new("RGBA", (div_w, div_h), (0, 0, 0, 0))
gd_d = ImageDraw.Draw(glow_d)
gd_d.text((div_w//2, mid_y), "◆", font=font_diamond, fill=(255, 0, 0, 150), anchor="mm")
glow_d = glow_d.filter(ImageFilter.GaussianBlur(15))
div_img = Image.alpha_composite(glow_d, div_img)

div_img.save(f"{WORKDIR}/divider.png", "PNG")
print(f"✅ divider.png {div_img.size}")

# ═══════════════════════════════════════════
#  ◆ SXB ◆ (مع ◆ على الجانبين)
# ═══════════════════════════════════════════
user_img = Image.open(f"{WORKDIR}/user.png").convert("RGBA")

# ◆ يسار
di_size = 55
di_font = load_font(FONT_EN, di_size, 700)
tmp_d = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
td_d = ImageDraw.Draw(tmp_d)
di_bb = td_d.textbbox((0, 0), "◆", font=di_font)
di_w = di_bb[2] - di_bb[0]
di_h = di_bb[3] - di_bb[1]

gap_between = 35
total_w = di_w + gap_between + user_img.width + gap_between + di_w
total_h = max(user_img.height, di_h + 40)

user_wrap = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
ud = ImageDraw.Draw(user_wrap)

# ◆ يسار
lx = 0
ly = (total_h - di_h) // 2 - di_bb[1]
ud.text((lx, ly), "◆", font=di_font, fill=(255, 0, 0, 255))

# النص
nx = di_w + gap_between
ny = (total_h - user_img.height) // 2
user_wrap.alpha_composite(user_img, (nx, ny))

# ◆ يمين
rx = total_w - di_w
ud.text((rx, ly), "◆", font=di_font, fill=(255, 0, 0, 255))

# توهج ◆ ◆
glow_di = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
gd_di = ImageDraw.Draw(glow_di)
gd_di.text((lx, ly), "◆", font=di_font, fill=(255, 0, 0, 150))
gd_di.text((rx, ly), "◆", font=di_font, fill=(255, 0, 0, 150))
glow_di = glow_di.filter(ImageFilter.GaussianBlur(18))
user_wrap = Image.alpha_composite(glow_di, user_wrap)

user_wrap.save(f"{WORKDIR}/user_wrap.png", "PNG")
print(f"✅ user_wrap.png {user_wrap.size}")

# ═══════════════════════════════════════════
#  الشعار
# ═══════════════════════════════════════════
try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo_data = urllib.request.urlopen(req, timeout=25).read()
    logo = Image.open(io.BytesIO(logo_data)).convert("RGBA")
    ratio = LOGO_W / logo.width
    logo = logo.resize((LOGO_W, int(logo.height * ratio)), Image.LANCZOS)
    logo.save(f"{WORKDIR}/logo.png", "PNG")
    print(f"✅ logo.png {logo.size}")
except Exception as e:
    print(f"⚠️ logo fail: {e}")
    ph = Image.new("RGBA", (LOGO_W, LOGO_W), (0, 0, 0, 0))
    ph.save(f"{WORKDIR}/logo.png", "PNG")

print("✅ اكتمل")
PYEOF

echo "🎨 توليد الصور..."
python3 /tmp/make_sxb.py
[ ! -s "$WORKDIR/bg.png" ] && { echo "❌ فشل التوليد"; exit 1; }

# ═══════════════════════════════════════════════════
#  FIFO
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═══════════════════════════════════════════════════
#  منتج شاشة الانتظار (متحركة)
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ تشغيل الشاشة المتحركة..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -loop 1 -framerate $FPS -i "$WORKDIR/bg.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/topbar.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/title.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/divider.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/sub.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/user_wrap.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/logo.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -filter_complex "\
[0:v]format=rgba[bg];\
[1:v]format=rgba[bar];\
[bg][bar]overlay=x=(W-w)/2:y=40[v1];\
[2:v]format=rgba[t];\
[v1][t]overlay=x=(W-w)/2:y=$Y_TITLE[v2];\
[3:v]format=rgba[div];\
[v2][div]overlay=x=(W-w)/2:y=$Y_DIVIDER[v3];\
[4:v]format=rgba[sub];\
[v3][sub]overlay=x=(W-w)/2:y=$Y_SUB[v4];\
[5:v]format=rgba[u];\
[v4][u]overlay=x=(W-w)/2:y=$Y_USER[v5];\
[6:v]format=rgba,scale='$LOGO_W*(1+0.05*sin(2*PI*t/4))':-1:eval=frame[logo_anim];\
[v5][logo_anim]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='between(mod(t\,$LOGO_CYCLE)\,0.3\,$LOGO_SHOW)'[v6];\
[v6]eq=brightness='0.015*sin(2*PI*t/5)':eval=frame[vout]" \
        -map "[vout]" -map 7:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -r $FPS -g $GOP \
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
    echo "🔴 منتج مباشر: $STREAMER"
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
#  المخرج
# ═══════════════════════════════════════════════════
start_output() {
    echo "🔗 الاتصال بـ Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -f mpegts -i "$FIFO" \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -g $GOP -r $FPS \
        -b:v 6500k -maxrate 7000k -bufsize 14000k \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 6
    if ! kill -0 "$OUT" 2>/dev/null; then
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
#  التشغيل
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."

start_producer_standby
sleep 5
kill -0 "$PROD" 2>/dev/null || { echo "❌ المنتج مات"; cat /tmp/prod.log; exit 1; }
echo "✅ شاشة الانتظار شغالة (PID: $PROD)"

start_output || exit 1

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

while true; do
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer
        sleep 2
        start_output || exit 1
        sleep 2
        continue
    fi

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

    URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
          --stream-timeout 15 "https://kick.com/$STREAMER" best \
          --stream-url 2>/dev/null | grep -m1 "^http")

    if [ -n "$URL" ]; then
        if [ "$MODE" != "LIVE" ]; then
            echo "🎯 SXB بدأ البث!"
            kill_producer
            sleep 1
            start_producer_live "$URL"
            sleep 6
            if kill -0 "$PROD" 2>/dev/null; then
                MODE="LIVE"
                echo "✅ مباشر: SXB"
            else
                echo "⚠️ فشل"
                MODE="NONE"
            fi
        fi
    else
        if [ "$MODE" != "STANDBY" ]; then
            echo "⏳ SXB توقف — عودة للانتظار"
            kill_producer
            sleep 1
            start_producer_standby
            sleep 3
            MODE="STANDBY"
        fi
    fi

    TICK=$((TICK + 1))
    if [ $((TICK % 4)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] $MODE | OUT=$OS | PROD=$PS ──"
    fi

    sleep 15
done
