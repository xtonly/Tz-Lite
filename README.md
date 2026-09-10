# Tz-Lite


apt update -y && apt install -y dnsutils curl && FILE="Lite.sh" && curl -sSL -H "Accept: application/vnd.github.v3.raw" -o $FILE "https://api.github.com/repos/xtonly/Tz-Lite/contents/Lite.sh?ref=main" && chmod +x $FILE && ./$FILE
