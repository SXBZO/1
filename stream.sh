#!/bin/bash
set -u

KICK_CHANNEL="${KICK_CHANNEL:-SXB}"
RESTREAM_KEY="${RESTREAM_KEY:?RESTREAM_KEY required}"
RESTREAM_URL="${RESTREAM_URL:-rtmp://live.restream.io/live}"
PLACEHOLDER_IMAGE="${PLACEHOLDER_IMAGE:-placeholder.png}"

MAX_STREAM_SEC=19200      # 320 دقيقة = حد البث لكل جولة
TRIGGER_AT_SEC=18000      # إطلاق التشغيل التالي عند الدقيقة 300

START_TS=$(date +%s)
TRIGGER_ATTEMPTED=0
TRIGGER_PID=""
TRIGGER_OK_FILE="/tmp/trigger_ok_$$"
rm -f "$TRIGGER_OK_FILE"

trigger_next() {
    echo "[$(date)] Triggering next chain run..."
    for attempt in $(seq 1 10); do
        CODE=$(curl -s -o /tmp/trigger_resp_$$ -w "%{http_code}" \
            -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/dispatches" \
            -d "{\"event_type\":\"chain-trigger\",\"client_payload\":{\"parent_run\":\"${GITHUB_RUN_ID}\"}}")
        if [ "$CODE" = "204" ]; then
            echo "[$(date)] Trigger OK (attempt $attempt)"
            touch "$TRIGGER_OK_FILE"
            return 0
        fi
        echo "[$(date)] Trigger failed HTTP=$CODE (attempt $attempt)"
        sleep 10
    done
    echo "[$(date)] Trigger FAILED after 10 attempts"
    return 1
}

run_stream() {
    local duration="$1" url="$2"
    timeout "${duration}s" ffmpeg -y -hide_banner -loglevel warning \
        -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 2 \
        -rw_timeout 10000000 \
        -i "$url" \
        -c copy \
        -f flv "${RESTREAM_URL}/${RESTREAM_KEY}" 2>/dev/null &
    echo $!
}

run_placeholder() {
    local duration="$1"
    if [ ! -f "$PLACEHOLDER_IMAGE" ]; then
        echo ""
        return 1
    fi
    timeout "${duration}s" ffmpeg -y -hide_banner -loglevel error \
        -re -loop 1 -framerate 30 -i "$PLACEHOLDER_IMAGE" \
        -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
        -c:v libx264 -preset veryfast -tune stillimage -pix_fmt yuv420p \
        -g 60 -b:v 2500k -maxrate 2500k -bufsize 5000k \
        -c:a aac -b:a 128k -ar 44100 \
        -shortest -f flv "${RESTREAM_URL}/${RESTREAM_KEY}" 2>/dev/null &
    echo $!
}

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TS))

    if [ "$ELAPSED" -ge "$MAX_STREAM_SEC" ]; then
        echo "[$(date)] MAX_STREAM_SEC reached, exiting."
        break
    fi

    if [ "$TRIGGER_ATTEMPTED" -eq 0 ] && [ "$ELAPSED" -ge "$TRIGGER_AT_SEC" ]; then
        TRIGGER_ATTEMPTED=1
        trigger_next &
        TRIGGER_PID=$!
    fi

    REMAINING=$((MAX_STREAM_SEC - ELAPSED))
    STREAM_URL=$(yt-dlp -g --no-warnings "https://kick.com/${KICK_CHANNEL}" 2>/dev/null | head -n 1)

    if [ -z "$STREAM_URL" ]; then
        SEG=$(( REMAINING < 60 ? REMAINING : 60 ))
        echo "[$(date)] Channel offline. Placeholder for ${SEG}s."
        FF_PID=$(run_placeholder "$SEG") || FF_PID=""
    else
        echo "[$(date)] Streaming. Remaining budget=${REMAINING}s."
        FF_PID=$(run_stream "$REMAINING" "$STREAM_URL")
    fi

    if [ -z "$FF_PID" ]; then
        echo "[$(date)] ffmpeg failed to start, retrying in 30s."
        sleep 30
        continue
    fi

    while kill -0 "$FF_PID" 2>/dev/null; do
        NOW=$(date +%s)
        if [ $((NOW - START_TS)) -ge "$MAX_STREAM_SEC" ]; then
            kill "$FF_PID" 2>/dev/null || true
            break
        fi
        sleep 5
    done
    wait "$FF_PID" 2>/dev/null || true

    NOW=$(date +%s)
    if [ $((NOW - START_TS)) -ge "$MAX_STREAM_SEC" ]; then
        break
    fi
done

# اجمع أي trigger معلّق
if [ -n "$TRIGGER_PID" ]; then
    echo "[$(date)] Waiting for pending trigger..."
    wait "$TRIGGER_PID" 2>/dev/null || true
fi

# إذا لم يُطلق أي trigger بعد (جولة قصيرة)، أطلقه الآن
if [ "$TRIGGER_ATTEMPTED" -eq 0 ]; then
    echo "[$(date)] Trigger never fired. Final attempt."
    trigger_next 10 || echo "FINAL TRIGGER FAILED"
fi

# تحقق نهائي
if [ -f "$TRIGGER_OK_FILE" ]; then
    echo "[$(date)] Next chain run confirmed triggered."
else
    echo "[$(date)] !! NEXT RUN TRIGGER FAILED - cron will recover within 6h."
fi

exit 0
