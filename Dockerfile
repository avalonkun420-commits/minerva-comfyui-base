# MINERVA VIGGLE LAB v1 - THIN WRAPPER
FROM runpod/comfyui:1.4.6-cuda13.0

COPY minerva-start.sh /opt/minerva/minerva-start.sh
COPY status.sh /opt/minerva/status.sh

RUN chmod +x /opt/minerva/minerva-start.sh /opt/minerva/status.sh

ENTRYPOINT ["/opt/minerva/minerva-start.sh"]
