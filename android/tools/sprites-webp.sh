#!/bin/sh
# Regenera os sprites do Android (res/drawable-nodpi/*.webp) a partir dos imagesets do iOS, sem perda.
# Uso: CWEBP=/caminho/cwebp android/tools/sprites-webp.sh   (cwebp vem do libwebp: https://developers.google.com/speed/webp/download)
set -e
cd "$(dirname "$0")/../.."
CWEBP=${CWEBP:-cwebp}
OUT=android/app/src/main/res/drawable-nodpi
mkdir -p "$OUT"
for d in ios/GymBros/Resources/Assets.xcassets/sprite_*.imageset; do
    name=$(basename "$d" .imageset)
    f=$(ls "$d"/*.png | head -1)
    "$CWEBP" -quiet -lossless -z 9 -m 6 "$f" -o "$OUT/$name.webp"
done
echo "$(ls "$OUT" | wc -l | tr -d ' ') sprites em $OUT"
