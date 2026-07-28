#!/usr/bin/env bash
# Batch-render the long-form modulation presets (one per model) to mp4.
#   scripts/render-batch.sh [duration_sec] [model:preset ...]
# With no preset args, renders the full long-form set below. Duration defaults
# to 300 (a full 5-min piece); pass e.g. 60 for quick proofs.
# Needs a display (like render.sh) — wrap with xvfb-run if headless:
#   xvfb-run -a scripts/render-batch.sh 60
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUR="${1:-300}"; shift || true

# Long-form set (one preset per model). Override by passing model:preset args.
SET=(
  "radial_burst:pulsar"
  "supernova_orbit:odyssey"
  "peg_cascade:clockwork"
  "chromatic_cascade:fresco"
  "matter_cycle:tides"
  "fluid_swirl:aurora"
  "metro_rise:century"
)
[[ $# -gt 0 ]] && SET=("$@")

echo "batch: ${#SET[@]} preset(s) @ ${DUR}s -> $ROOT/renders/"
for entry in "${SET[@]}"; do
  model="${entry%%:*}"; preset="${entry##*:}"
  echo "=== $model / $preset ==="
  "$ROOT/scripts/render.sh" "$model" "$preset" "$DUR"
done
echo "batch done -> $ROOT/renders/"
