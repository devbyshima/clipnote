#!/bin/bash
# Builds ClipnoteTests/Fixtures/sample.mp4: three slides with on-screen text,
# narrated by the system voice, plus burned-in captions on the last slide.
# The integration test checks the note Clipnote makes from it.
#
#   ./scripts/make-test-video.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/clipnote-sample"
OUT="$ROOT/ClipnoteTests/Fixtures/sample.mp4"
rm -rf "$WORK" && mkdir -p "$WORK"

slide() { # name, title, line1, line2, caption
  cat > "$WORK/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720">
  <rect width="1280" height="720" fill="#101418"/>
  <text x="100" y="200" font-family="Helvetica Neue" font-weight="bold" font-size="72" fill="#ffffff">$2</text>
  <text x="100" y="330" font-family="Helvetica Neue" font-size="44" fill="#d0d6dc">$3</text>
  <text x="100" y="410" font-family="Helvetica Neue" font-size="44" fill="#d0d6dc">$4</text>
  <text x="640" y="660" text-anchor="middle" font-family="Helvetica Neue" font-size="34" fill="#ffd60a">$5</text>
</svg>
SVG
  rsvg-convert "$WORK/$1.svg" -o "$WORK/$1.png"
}

slide s1 "Quarterly Planning Review" "Revenue grew 18 percent" "Launch date: March 14" ""
slide s2 "Three Priorities" "1. Hire two engineers" "2. Ship the mobile beta" ""
slide s3 "Next Steps" "Budget review on Friday" "Owner: Priya Raman" "We meet again on Friday to review the budget."

say -v Samantha -o "$WORK/a1.aiff" "Welcome to the quarterly planning review. This quarter, revenue grew eighteen percent, and the launch is set for March fourteenth."
say -v Samantha -o "$WORK/a2.aiff" "We have three priorities. First, we will hire two engineers. Second, we will ship the mobile beta before the summer."
say -v Samantha -o "$WORK/a3.aiff" "We meet again on Friday to review the budget. Priya will own the follow up."

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
D1=$(python3 -c "print(round($(dur "$WORK/a1.aiff") + 1.0, 2))")
D2=$(python3 -c "print(round($(dur "$WORK/a2.aiff") + 1.0, 2))")
D3=$(python3 -c "print(round($(dur "$WORK/a3.aiff") + 1.5, 2))")

for i in 1 2 3; do
  eval "D=\$D$i"
  ffmpeg -v error -y -loop 1 -t "$D" -i "$WORK/s$i.png" -i "$WORK/a$i.aiff" \
    -af apad -t "$D" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 48000 -ac 2 \
    "$WORK/part$i.mp4"
done
printf "file '%s'\n" "$WORK/part1.mp4" "$WORK/part2.mp4" "$WORK/part3.mp4" > "$WORK/list.txt"
ffmpeg -v error -y -f concat -safe 0 -i "$WORK/list.txt" -c copy -movflags +faststart "$OUT"
echo "$OUT ($(dur "$OUT")s)"
