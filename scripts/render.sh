#!/usr/bin/env bash
# Render a model+preset to mp4: scripts/render.sh <model_dir> <preset_name> [duration_sec]
set -euo pipefail
MODEL="${1:?usage: render.sh <model> <preset> [duration]}"
PRESET="${2:?usage: render.sh <model> <preset> [duration]}"
DUR="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESET_PATH="$ROOT/$MODEL/presets/$PRESET.json"
[[ -f "$PRESET_PATH" ]] || { echo "no such preset: $PRESET_PATH" >&2; exit 1; }
OUT="$ROOT/renders"; mkdir -p "$OUT"
NAME="${MODEL}_${PRESET}"
# Models with their own renderer (hydra: headless Chromium) write the mp4 directly.
if [[ -f "$ROOT/$MODEL/render.mjs" ]]; then
  ARGS=(--preset "$PRESET_PATH" --out "$OUT/$NAME.mp4")
  [[ -n "$DUR" ]] && ARGS+=(--duration "$DUR")
  node "$ROOT/$MODEL/render.mjs" "${ARGS[@]}"
  echo "rendered: $OUT/$NAME.mp4"
  exit 0
fi
AVI="$OUT/$NAME.avi"
ARGS=(--path "$ROOT/$MODEL" --write-movie "$AVI" --fixed-fps 60 -- --preset "$PRESET_PATH")
[[ -n "$DUR" ]] && ARGS+=(--duration "$DUR")
godot "${ARGS[@]}"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -crf 18 -pix_fmt yuv420p -an "$OUT/$NAME.mp4"
rm -f "$AVI"
echo "rendered: $OUT/$NAME.mp4"
