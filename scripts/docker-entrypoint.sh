#!/bin/bash
set -e

# Start Xvfb virtual display if DISPLAY is :99
if [ "$DISPLAY" = ":99" ]; then
    echo "Starting Xvfb virtual display on :99..."
    Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +extension RENDER -noreset &
    sleep 1

    if command -v openbox >/dev/null 2>&1; then
        echo "Starting Openbox window manager..."
        openbox &
    fi

    if command -v x11vnc >/dev/null 2>&1; then
        echo "Starting x11vnc server on port 5900..."
        x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -bg -o /tmp/x11vnc.log
    fi
fi

exec "$@"
