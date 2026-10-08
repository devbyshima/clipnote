#!/bin/bash
# Downloads the Whisper model and tokenizer that get bundled inside the app.
# Run once after cloning; the build copies Models/Whisper into Ovyl.app.
#
#   ./scripts/fetch-models.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="openai_whisper-large-v3-v20240930_turbo_632MB"
MODEL_REPO="https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main"
TOKENIZER_REPO="https://huggingface.co/openai/whisper-large-v3/resolve/main"
DEST="$ROOT/Models/Whisper"

MODEL_FILES=(
  config.json
  generation_config.json
  AudioEncoder.mlmodelc/analytics/coremldata.bin
  AudioEncoder.mlmodelc/coremldata.bin
  AudioEncoder.mlmodelc/metadata.json
  AudioEncoder.mlmodelc/model.mil
  AudioEncoder.mlmodelc/weights/weight.bin
  MelSpectrogram.mlmodelc/analytics/coremldata.bin
  MelSpectrogram.mlmodelc/coremldata.bin
  MelSpectrogram.mlmodelc/metadata.json
  MelSpectrogram.mlmodelc/model.mil
  MelSpectrogram.mlmodelc/weights/weight.bin
  TextDecoder.mlmodelc/analytics/coremldata.bin
  TextDecoder.mlmodelc/coremldata.bin
  TextDecoder.mlmodelc/metadata.json
  TextDecoder.mlmodelc/model.mil
  TextDecoder.mlmodelc/weights/weight.bin
  TextDecoderContextPrefill.mlmodelc/analytics/coremldata.bin
  TextDecoderContextPrefill.mlmodelc/coremldata.bin
  TextDecoderContextPrefill.mlmodelc/metadata.json
  TextDecoderContextPrefill.mlmodelc/model.mil
  TextDecoderContextPrefill.mlmodelc/weights/weight.bin
)
TOKENIZER_FILES=(tokenizer.json tokenizer_config.json)

fetch() {
  local url="$1" out="$2"
  if [ -s "$out" ]; then return 0; fi
  mkdir -p "$(dirname "$out")"
  echo "  $(basename "$(dirname "$out")")/$(basename "$out")"
  curl -fL --retry 5 --retry-delay 2 -C - -o "$out.part" "$url"
  mv "$out.part" "$out"
}

echo "Whisper model ($VARIANT)"
for f in "${MODEL_FILES[@]}"; do
  fetch "$MODEL_REPO/$VARIANT/$f" "$DEST/model/$f"
done

echo "Tokenizer"
for f in "${TOKENIZER_FILES[@]}"; do
  fetch "$TOKENIZER_REPO/$f" "$DEST/tokenizer/$f"
done

echo "$VARIANT" > "$DEST/model/VARIANT"
du -sh "$DEST"
