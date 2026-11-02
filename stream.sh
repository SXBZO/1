#!/bin/bash

# ================== الإعدادات ==================
KICK_CHANNEL="SXB"
RESTREAM_KEY="re_12552561_event81737fba9ada4713ab13ad7e04a36880"
RESTREAM_URL="rtmp://live.restream.io/live"
PLACEHOLDER_IMAGE="placeholder.png"   # ضع صورة شعار SXB بهذا الاسم في الريبو
# ===============================================

# دالة تشغيل شاشة الانتظار لمدة محددة (بالثواني)
play_placeholder() {
    local DURATION="$1"
    echo "[$(date)] عرض شاشة الانتظار لمدة ${DURATION} ثانية..."
    timeout "${DURATION}s" ffmpeg -y -hide_banner -loglevel warning \
        -re -loop 1 -framerate 30 -i "$PLACEHOLDER_IMAGE" \
        -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
        -c:v libx264 -preset veryfast -tune stillimage -pix_fmt yuv420p \
        -g 60 -b:v 2500k -maxrate 2500k -bufsize 5000k \
        -c:a aac -b:a 128k -ar 44100 \
        -shortest -f flv "${RESTREAM_URL}/${RESTREAM_KEY}"
}

while true; do
    echo "[$(date)] فحص قناة كيك: $KICK_CHANNEL ..."
    STREAM_URL=$(yt-dlp -g --no-warnings "https://kick.com/${KICK_CHANNEL}" 2>/dev/null | head -n 1)

    # الحالة 1: القناة غير متصلة (offline)
    if [ -z "$STREAM_URL" ]; then
        echo "[$(date)] القناة غير متصلة — عرض شاشة الانتظار 60 ثانية"
        play_placeholder 60
        sleep 3
        continue
    fi

    echo "[$(date)] البث متاح — نسخ مباشر (-c copy) ..."

    # الحالة 2: البث شغّال — نسخه كما هو مع كشف التعليق
    timeout 3600s ffmpeg -hide_banner -loglevel warning \
        -rw_timeout 10000000 \
        -i "$STREAM_URL" \
        -c copy -f flv "${RESTREAM_URL}/${RESTREAM_KEY}"

    # الحالة 3: توقف/علّق البث — شاشة انتظار قصيرة قبل إعادة المحاولة
    echo "[$(date)] توقف البث — عرض شاشة الانتظار 30 ثانية"
    play_placeholder 30
    sleep 3
done
