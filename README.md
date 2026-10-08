# Ovyl

A Mac app that turns videos and pictures into formatted notes. Drop in a video and Ovyl:

- transcribes the speech, and recognizes songs and other music instead of transcribing the lyrics,
- reads text that appears on screen and tells apart subtitles, titles that stay on screen, slides, and remarks (commentary),
- keeps one version where subtitles repeat the speech: the transcript, or the subtitles where the speech engine was unsure, missed words, or heard nothing,
- makes the captions the note's text when a video has no speech (only music, or no sound),
- writes a note with a title, summary, key points, and sections, with on-screen text placed where it appeared.

Drop in pictures (screenshots, photos of pages or whiteboards) and Ovyl reads their text into one note, a section per picture, in file name order.

Everything runs on the Mac. The app has no network entitlement.

## How it works

| Step | Engine | Where it comes from |
|------|--------|---------------------|
| Speech | Whisper large-v3 turbo (WhisperKit, Core ML) | Bundled in the app (about 650 MB) |
| Speech fallback | Apple SpeechAnalyzer | Built into macOS |
| Music and singing | Apple SoundAnalysis classifier | Built into macOS |
| On-screen text | Apple Vision text recognition | Built into macOS |
| Text in pictures | Apple Vision document recognition | Built into macOS |
| Title, summary, headings | Apple Foundation Models | Built into macOS (Apple Intelligence) |

- **Speech:** Automatic mode uses Whisper first (most accurate, about 100 languages, detects the language), then Apple Speech if Whisper can't run. Settings can put Apple Speech first.
- **Music:** the soundtrack is classified in 3-second windows. Singing, or music with little talking, is silenced before Whisper runs and left out of the transcript; the note marks where it played. Talking over background music is still transcribed. Settings can turn this off.
- **On-screen text:** frames are sampled every second (every 2 to 3 seconds for long videos) and unchanged frames are skipped. `ScreenTextSorter` then sorts the text:
  - text on screen in most frames is a watermark (handles, app marks, web addresses, tiny print; dropped) or, if it's a line or two, a title shown once at the top. More unchanging text is the video's content and stays a slide;
  - short text that changes along with the speech, and accounts for most of what's said while it shows, is a subtitle. The transcript is kept, except where the speech engine was unsure (low confidence) or missed words, or heard nothing while the sound classifier hears talking; there the subtitles are used;
  - without speech, short text that keeps changing in one place is the captions, and becomes the note's text;
  - everything else is grouped into moments: slides (with a frame grab) and remarks (a line or two that isn't said).
- **Pictures:** each picture is read with Vision's document reader, which keeps paragraphs, lists, and tables.
- **Formatting:** the language model only writes the title, summary, key points, and headings. The transcript is never reworded. Without Apple Intelligence, notes still get slide titles as headings and a title from the opening slide or the file name.

## Performance

Measured on the dev Mac with `./scripts/build.sh bench`, on about 3 minutes of speech:

| Whisper runs on | First-ever load | Later loads | Transcription |
|-----------------|-----------------|-------------|---------------|
| Neural Engine | 300 s (one-time compile) | 4 s | 14x real time (4 chunks at a time; 11x one at a time) |
| Hybrid: GPU encoder, Neural Engine decoder | about 50 s | 4 s | 4.5x real time |
| GPU | 47 s | 3 s | 2.8x real time |

The Neural Engine is the fastest and uses the least power, but the first time a Mac loads the model, Core ML compiles it for that Mac's Neural Engine. Apple doesn't let apps ship that compiled form, and it's cached per model location and OS version. `WhisperService` handles this:

- **First launch:** the hybrid loads first, so videos transcribe after about a minute (66 s measured from a cold start), while the Neural Engine compiles in the background (about 6 minutes). Then every video uses the Neural Engine and the hybrid is unloaded.
- **Later launches:** the Neural Engine loads directly (about 5 to 12 s). If Core ML dropped its cache (after an OS update, for example), the hybrid takes over after 8 seconds and the compile runs again in the background.
- **Idle:** after 15 minutes without videos the model is unloaded to free memory.

Other efficiency choices: Apple Intelligence is warmed up while speech is transcribed, unchanged video frames skip text recognition, and frames are checked half as often in Low Power Mode or when the Mac runs hot.

Keep the app in one place (for example /Applications). A rebuilt or moved copy needs the Neural Engine compile again.

## Building

Requires macOS 27 and Xcode 27, plus `xcodegen` (Homebrew).

```bash
./scripts/fetch-models.sh     # once: downloads the Whisper model into Models/
./scripts/make-test-video.sh  # once: makes the test videos and pictures (needs ffmpeg and rsvg-convert)
./scripts/build.sh            # Debug build in .build/main
./scripts/build.sh test       # unit tests and an end-to-end run on the test video
./scripts/build.sh release    # Release build, copied to build/Ovyl.app
./scripts/build.sh bench      # Whisper load and speed benchmarks
```

Signing uses `DEVELOPMENT_TEAM` in `project.yml`; set it to your own team ID.

The test fixtures are three narrated slides with a burned-in caption, narration with matching subtitles over quiet music, a sung song with captions, captions with no sound, and two pictures. They aren't in the repository because most use a macOS system voice, which Apple's license doesn't allow sharing publicly, so the script makes them on your Mac. `./scripts/build.sh test -only-testing:OvylTests/SnapshotTests` renders the main screens offscreen; the PNGs are printed into `.build/main/build.log` as `SNAPSHOT <name> <base64>` lines, since the app container is private.

## Layout

- `Ovyl/Pipeline`: audio decoding, music detection, Whisper and Apple Speech engines, on-screen text reader and sorter, picture reader, note composer, smart formatter.
- `Ovyl/Model`: the SwiftData `Note`, its JSON content, Markdown export.
- `Ovyl/UI`: SwiftUI views.
- `OvylTests`: Swift Testing unit tests and `PipelineIntegrationTests`.

## Credits

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax (MIT) runs Whisper with Core ML.
- [Whisper](https://github.com/openai/whisper) by OpenAI; the Core ML conversion is [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) (MIT) and the tokenizer comes from [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3) (Apache 2.0). Both are downloaded by `scripts/fetch-models.sh`, not stored here.

## License

Ovyl is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You may use, study and change it for any non-commercial purpose. Selling it, or using it in
anything that earns money, is not allowed. The first published version, released under MIT, remains under MIT.

The Ovyl name and icon are not covered by the license: a modified version must use its own
name and icon.
