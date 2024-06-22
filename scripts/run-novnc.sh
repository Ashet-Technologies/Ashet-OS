#!/bin/sh

# exec docker run \
#     --rm \
#     -ti \
#     --name novnc \
#     -p 8080:6080 \
#     -e AUTOCONNECT=true \
#     -e VNC_SERVER=172.17.0.1:5900 \
#     -e VIEW_ONLY=false \
#     bonigarcia/novnc:1.1.0

exec docker run \
    --rm \
    -ti \
    --name novnc \
    -p 8080:8081 \
    -e REMOTE_HOST=172.17.0.1 \
    -e REMOTE_PORT=5900 \
    dougw/novnc
