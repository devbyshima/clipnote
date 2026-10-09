#!/bin/bash
# Builds the test fixtures in OvylTests/Fixtures:
#   sample.mp4           three slides narrated by a system voice, with a
#                        burned-in caption on the last slide
#   captions-speech.mp4  narration with matching subtitles over quiet music,
#                        a headline shown throughout, a remark, a watermark
#   captions-music.mp4   a sung song with captions, a headline, a watermark
#   captions-silent.mp4  captions only, no sound at all
#   picture-*.png        a packing list and a whiteboard, for picture notes
# The tests check the notes Ovyl makes from them.
#
#   ./scripts/make-test-video.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/ovyl-sample"
FIXTURES="$ROOT/OvylTests/Fixtures"
rm -rf "$WORK" && mkdir -p "$WORK" "$FIXTURES"

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
plus() { python3 -c "print(round($1 + $2, 2))"; }

# Joins part1.mp4, part2.mp4, ... in $WORK/$1 into $2.
join_parts() {
  local dir="$1" out="$2"
  ls "$dir"/part*.mp4 | sort -V | sed "s/.*/file '&'/" > "$dir/list.txt"
  ffmpeg -v error -y -f concat -safe 0 -i "$dir/list.txt" -c copy -movflags +faststart "$out"
  echo "$out ($(dur "$out")s)"
}

# MARK: sample.mp4

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

mkdir -p "$WORK/sample"
for i in 1 2 3; do
  D=$(plus "$(dur "$WORK/a$i.aiff")" $([ $i = 3 ] && echo 1.5 || echo 1.0))
  ffmpeg -v error -y -loop 1 -t "$D" -i "$WORK/s$i.png" -i "$WORK/a$i.aiff" \
    -af apad -t "$D" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 48000 -ac 2 \
    "$WORK/sample/part$i.mp4"
done
join_parts "$WORK/sample" "$FIXTURES/sample.mp4"

# MARK: Portrait captions, like a short video app

# card name, headline, caption line 1, caption line 2, remark, watermark
card() {
  cat > "$WORK/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="720" height="1280">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2b3a55"/><stop offset="1" stop-color="#0f1724"/>
  </linearGradient></defs>
  <rect width="720" height="1280" fill="url(#g)"/>
  <circle cx="560" cy="900" r="180" fill="#3d5a80" opacity="0.5"/>
  <text x="360" y="190" text-anchor="middle" font-family="Helvetica Neue" font-weight="bold" font-size="60" fill="#ffffff">$2</text>
  <text x="560" y="340" text-anchor="middle" font-family="Helvetica Neue" font-style="italic" font-size="34" fill="#ffd60a">$5</text>
  <rect x="50" y="$([ -n "$4" ] && echo 560 || echo 600)" width="620" height="$([ -n "$4" ] && echo 170 || echo 100)" rx="18" fill="#000000" opacity="0.55"/>
  <text x="360" y="$([ -n "$4" ] && echo 630 || echo 665)" text-anchor="middle" font-family="Helvetica Neue" font-weight="bold" font-size="44" fill="#ffffff">$3</text>
  <text x="360" y="700" text-anchor="middle" font-family="Helvetica Neue" font-weight="bold" font-size="44" fill="#ffffff">$4</text>
  <text x="680" y="1240" text-anchor="end" font-family="Helvetica Neue" font-size="24" fill="#c8d0da">$6</text>
</svg>
SVG
  rsvg-convert "$WORK/$1.svg" -o "$WORK/$1.png"
}

# Quiet chords, for music under speech and as the backing of the song.
chords() { # seconds, volume, output
  ffmpeg -v error -y \
    -f lavfi -i "aevalsrc='0.3*sin(2*PI*(220+110*floor(mod(t,4)/2))*t)+0.25*sin(2*PI*(277+93*floor(mod(t,4)/2))*t)+0.2*sin(2*PI*330*t)*(0.6+0.4*sin(2*PI*2*t))':s=48000:d=$1" \
    -af "volume=$2" -ac 2 "$3"
}

# MARK: captions-speech.mp4

mkdir -p "$WORK/speech"
SPEECH=(
  "Every morning I wake up at six.|Every morning I|wake up at six.|"
  "Then I drink a big glass of water.|Then I drink a big|glass of water.|(this changed my life)"
  "After that I go for a short walk outside.|After that I go for|a short walk outside.|"
  "And I write down three goals for the day.|And I write down three|goals for the day.|"
)
i=0
for entry in "${SPEECH[@]}"; do
  i=$((i + 1))
  IFS='|' read -r spoken line1 line2 remark <<< "$entry"
  card "speech$i" "MY MORNING ROUTINE" "$line1" "$line2" "$remark" "@morningwithme"
  say -v Samantha -o "$WORK/speech/v$i.aiff" "$spoken"
  D=$(plus "$(dur "$WORK/speech/v$i.aiff")" 0.7)
  ffmpeg -v error -y -loop 1 -t "$D" -i "$WORK/speech$i.png" -i "$WORK/speech/v$i.aiff" \
    -af apad -t "$D" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 48000 -ac 2 \
    "$WORK/speech/part$i.mp4"
done
ls "$WORK/speech"/part*.mp4 | sort -V | sed "s/.*/file '&'/" > "$WORK/speech/list.txt"
ffmpeg -v error -y -f concat -safe 0 -i "$WORK/speech/list.txt" -c copy "$WORK/speech/joined.mp4"
chords "$(dur "$WORK/speech/joined.mp4")" 0.06 "$WORK/speech/bed.wav"
ffmpeg -v error -y -i "$WORK/speech/joined.mp4" -i "$WORK/speech/bed.wav" \
  -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:normalize=0[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -ar 48000 -ac 2 -movflags +faststart "$FIXTURES/captions-speech.mp4"
echo "$FIXTURES/captions-speech.mp4 ($(dur "$FIXTURES/captions-speech.mp4")s)"

# MARK: captions-music.mp4

mkdir -p "$WORK/music"
SONG=16
say -v "Good News" -o "$WORK/music/voice.aiff" \
  "Sleep sleep sleep is my favorite thing. I dream all night until the morning light. Sleep sleep sleep, oh what a lovely thing."
ffmpeg -v error -y -stream_loop 3 -i "$WORK/music/voice.aiff" -t "$SONG" -ar 48000 -ac 2 "$WORK/music/voice.wav"
chords "$SONG" 0.5 "$WORK/music/backing.wav"
ffmpeg -v error -y -i "$WORK/music/voice.wav" -i "$WORK/music/backing.wav" \
  -filter_complex "amix=inputs=2:duration=longest:normalize=0" -ac 2 "$WORK/music/song.wav"
MUSIC=(
  "Put your phone away|by 10pm"
  "Keep your bedroom|cool and dark"
  "Wake up at the same|time every day"
  "Your body will|thank you"
)
i=0
for entry in "${MUSIC[@]}"; do
  i=$((i + 1))
  IFS='|' read -r line1 line2 <<< "$entry"
  card "music$i" "3 SLEEP TIPS" "$line1" "$line2" "" "@sleepcoach"
  ffmpeg -v error -y -loop 1 -t 4 -i "$WORK/music$i.png" -c:v libx264 -pix_fmt yuv420p -r 30 "$WORK/music/part$i.mp4"
done
ls "$WORK/music"/part*.mp4 | sort -V | sed "s/.*/file '&'/" > "$WORK/music/list.txt"
ffmpeg -v error -y -f concat -safe 0 -i "$WORK/music/list.txt" -i "$WORK/music/song.wav" \
  -map 0:v -map 1:a -c:v copy -c:a aac -ar 48000 -ac 2 -shortest -movflags +faststart "$FIXTURES/captions-music.mp4"
echo "$FIXTURES/captions-music.mp4 ($(dur "$FIXTURES/captions-music.mp4")s)"

# MARK: captions-silent.mp4

mkdir -p "$WORK/silent"
SILENT=("Step one: open the Settings app." "Step two: tap General, then About." "Step three: check the version number.")
i=0
for line in "${SILENT[@]}"; do
  i=$((i + 1))
  slide "silent$i" "" "" "" "$line"
  ffmpeg -v error -y -loop 1 -t 3 -i "$WORK/silent$i.png" -c:v libx264 -pix_fmt yuv420p -r 30 "$WORK/silent/part$i.mp4"
done
join_parts "$WORK/silent" "$FIXTURES/captions-silent.mp4"

# MARK: Pictures

cat > "$WORK/picture-1.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1500">
  <rect width="1200" height="1500" fill="#fbfaf6"/>
  <text x="100" y="170" font-family="Georgia" font-weight="bold" font-size="76" fill="#1d1d1f">Packing List</text>
  <text font-family="Georgia" font-size="38" fill="#2c2c2e">
    <tspan x="100" y="300">Bring the blue tent and two sleeping bags. The</tspan>
    <tspan x="100" y="355">forecast says rain on Saturday, so pack the rain</tspan>
    <tspan x="100" y="410">covers and an extra pair of socks.</tspan>
  </text>
  <text font-family="Georgia" font-size="38" fill="#2c2c2e">
    <tspan x="100" y="540">Leave by eight in the morning to reach the lake</tspan>
    <tspan x="100" y="595">before noon. Maya is bringing the camping stove.</tspan>
  </text>
</svg>
SVG
cat > "$WORK/picture-2.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1000">
  <rect width="1600" height="1000" fill="#ffffff"/>
  <rect x="20" y="20" width="1560" height="960" fill="none" stroke="#c7c7cc" stroke-width="8"/>
  <text x="120" y="190" font-family="Marker Felt" font-size="88" fill="#0a5bd8">Sprint Goals</text>
  <text x="120" y="360" font-family="Marker Felt" font-size="60" fill="#1d1d1f">Fix the login timeout bug</text>
  <text x="120" y="480" font-family="Marker Felt" font-size="60" fill="#1d1d1f">Ship dark mode to beta testers</text>
  <text x="120" y="600" font-family="Marker Felt" font-size="60" fill="#1d1d1f">Demo on Thursday at 3 pm</text>
</svg>
SVG
rsvg-convert "$WORK/picture-1.svg" -o "$FIXTURES/picture-1.png"
rsvg-convert "$WORK/picture-2.svg" -o "$FIXTURES/picture-2.png"
echo "$FIXTURES/picture-1.png, picture-2.png"

# The same narration with no picture, as an audio-only recording.
ffmpeg -loglevel error -y -i "$FIXTURES/sample.mp4" -vn -c:a aac -b:a 48k "$FIXTURES/sample-audio.m4a"
echo "$FIXTURES/sample-audio.m4a"
