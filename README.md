# Ovyl

A Mac app that turns videos, audio recordings and pictures into formatted notes. Drop in a video or a recording and Ovyl:

- transcribes the speech, and recognizes songs and other music instead of transcribing the lyrics,
- reads text that appears on screen and tells apart subtitles, titles that stay on screen, slides, and remarks (commentary),
- keeps one version where subtitles repeat the speech: the transcript, or the subtitles where the speech engine was unsure, missed words, or heard nothing,
- makes the captions the note's text when a video has no speech (only music, or no sound),
- writes a note with a title, summary, key points, and sections, with on-screen text placed where it appeared.

Drop in pictures (screenshots, photos of pages or whiteboards) and Ovyl reads their text into one note, a section per picture, in file name order.

Notes are made on the Mac. The only network use is the assistant, when it's set to Claude (with your own API key) or Apple's Private Cloud Compute; by default it runs on the Mac too.

## The window

- **Left:** Home (every note), New (make a note from a video, audio or pictures), and the folders pinned to the sidebar, each with its count. Every folder is on Home; pin one from its pill, its menu, the pin button on its page, or by carrying its card onto the sidebar, and unpin it the same ways. Drag notes onto a folder here to file them. The + beside Folders makes a pinned folder, ready to name.
- **Middle:** Home as cards: the folders as colored folder cards with a sheet showing for each note inside, and the notes outside them as cards with their title, the start of their text and the day. Cards fill columns as they fit; a note with text stands twice as tall. The folder button in Home's toolbar makes a folder, on Home and not pinned, with its name ready to type on its card. A folder card shows its name in the middle of its front, shrinking to fit a long one, and a pin beside it when the folder is pinned. A folder's dots bring up a pill to rename, color, pin or delete it, and the pill gives way to what it opens: Rename edits the name right on the card (Return or clicking away keeps it, Escape drops it), and its color button opens a color flower (twelve rich earth tones, among them brown, teal, the app's green and graphite, around six light ones and an off-white). A folder card's sheets are the note cards' color, light or dark. Drop notes on a folder card to file them. A folder shows its notes the same way. The view menu switches between the messy grid, an even grid and a list (with the cards as thumbnails), sorts by date made, date edited or title either way, or by hand: pick up a card or row and carry it into any order (each page keeps its own). The card lifts with a deeper shadow and leans into its motion, the others slide aside on springs as it passes, the page scrolls when it nears the top or bottom, and on release it settles into its place. A note carried onto a folder, on the page or in the sidebar, sinks into it; held at a folder's edge for a moment, it takes the folder's place instead. It can put folders first and hide note text; the slider at the bottom sizes the cards, smallest at first. Or the open note. A note opens in reader mode with just its title and text, with a Sans or Serif choice and a text size at the bottom. Edit (⌘E) edits its Markdown, showing the syntax only on the line being edited; selecting text brings up a formatting bar, and ⌘B, ⌘I and ⌘K work. Copy copies the note as Markdown. Timestamps in the note are links that play the video from that moment.
- **Right:** the note's video on a dotted canvas, with Frames (F), Info (I) and Delete (D) under it; recordings have no frames, so they have no Frames button. Frames moves the frames grabbed from on-screen text into the middle as a grid; Info moves the video into the middle and shows its details on the right. The note's Info button shows its details and summary on the right instead. Every view in the right pane starts with its way out: Back when it opened from something (the details go back to the note or the frames, the note's info back to its video), Close when it's the pane's first view. Back and forward (⌘[ and ⌘]) work everywhere.

The empty states (a new Home, an empty folder, a search with no results, a video with no text on screen, and a video or recording that was moved, with a way to locate it) fit any pane: cards and their handwritten remarks only appear where they fit whole, the headline steps down in size for narrow panes, and the whole scene grows on large displays.

Both side panes slide away (⌘. for the left, ⌘P for the right), and the right one resizes by dragging its edge. New notes go into the folder you're looking at. ⌘N or ⌘O makes a note, ⇧⌘N makes a pinned folder.

Search (⌘F) goes through everything in the notes, not only titles: what was said, text on screen, text in pictures, and edited text. Results are ranked, and each shows where it matched (a time, a frame, a picture) with the words marked.

## Assistant

The sparkles button (⌘J) opens the assistant on the right. Chat with it like any language model, about what's in Ovyl: it finds and reads notes, transcripts by time, and text from frames and pictures, and it can make, rewrite, add to, rename, move and open notes. Ask it to combine two notes into one, restructure a note so it reads well, or help you write. Its changes happen right away and each has Undo. The open note is attached to what you ask; earlier chats are under the clock button.

| Model | Where it runs |
|-------|---------------|
| On this Mac (default) | Apple Foundation Models, on the Mac |
| Apple Private Cloud | Apple's Private Cloud Compute |
| Claude (Fable 5.1, Opus 5.5, Sonnet 5.5, Haiku 5.5) | Anthropic, with your API key from Settings › Assistant, kept in the keychain |

The on-device model holds a few pages at a time, so it reads long notes in parts; the others read far more at once.

## Colors

Ovyl uses Beam's colors and controls, and follows the system's light or dark appearance. Every color comes from `Palette` (`Ovyl/UI/Palette.swift`):

- **Surfaces:** a pale sage `#F1F2EC` behind everything with `#FBFCF8` cards in light mode; graphite `#161616` with `#212121` cards in dark mode. Pure black is kept for the pages that show a video or recording. The sidebar, the notes and the right pane share the background, set apart by hairlines; text wells, chips and progress tracks are a wash of ink.
- **Text** is black and white, with `#747571` (light) and `#AAACA7` (dark) for secondary text.
- **Beam green `#B0C246` is the one accent,** in both modes: links, timestamps, the handwriting in the empty states, progress, and what's selected (a green wash with a green icon, as in Beam's sidebar).
- **Buttons are Beam's:** the main action is a capsule of green gradient with a black label and a soft glow in its own color, which dims and gives a little when pressed; secondary actions are capsules washed with ink and edged with a hairline. Floating bars are glass with a hairline edge.
- **Status colors:** green for done, the system's orange for warnings and red for failures.
- **Folders keep the colors you pick** with the color flower.
- **Settings is laid out as Beam's:** a sidebar of panes with the mark at the top, on the same background as the main sidebar, and each pane a large title over cards of rows split by hairlines, with green switches, capsule choices and values in small washed capsules.

## The logo

The mark is three slanted strokes, tallest first, standing on one line. The app icon is an Icon Composer document, `Ovyl/Resources/AppIcon.icon`: in Beam's icon colors, softly lit ink strokes on Beam green, and in dark mode green strokes with a pale edge on near-black under a green glow; clear and tinted icons get plain white strokes. Each stroke is its own layer, lit across its width from the top left. Open it in Icon Composer to change it.

While Ovyl works, the mark comes apart into simple shapes, acts out what's happening, and springs back together (`Ovyl/UI/Logo`):

| Motion | Only for | What the strokes do |
|--------|----------|---------------------|
| Opening | a video, recording or pictures opening | flow left one place at a time, the largest shrinking away as a new one grows in |
| Waiting | a note queued behind another | sway gently, one after another, and settle |
| Preparing | the speech model getting ready (in the sidebar and on a note) | pull into dots that circle the middle like a turning wheel |
| Listening | the audio being read and listened to for music | stand up as sound levels and keep bouncing |
| Transcribing | speech becoming text | sound levels that bounce, tip over into lines of text, and stand back up to listen |
| Reading | on-screen text and pictures being read | a scanner sweeps across and back, lines of text growing behind it and drawing in again |
| Writing | the note being written | lines written one after another, folded into a page, and opened out to write again |
| Thinking | the assistant before it answers | round into dots that hop in turn |
| Failed | a note that couldn't be made | wobble and tumble into a heap, where they stay, the ball now and then trying a hop |

Each motion has one purpose and is never borrowed for another. A note's motion follows its stage, matched to the pipeline's own step names.

A loader starts as the mark, turns into its own form, and stays in it, looping, until what it's waiting for is done; it never goes back to the mark. Switching stage carries the pieces on at the speed they're going, straight into the next loader. Every move is a spring, and each new move is added on top of the springs still running instead of starting from rest, so pieces carry their speed from one pose into the next and round the loop; beats can overlap, and nothing stops dead. Pieces travel in arcs, stretch along the way they move and squash as they set off and land; bars and lines that grow in place stay rigid. Frames are drawn off the main thread and cost about 25 µs each. With Reduce Motion the mark stays whole and breathes.

## Storage

Ovyl keeps your data apart from what it can make again, so it doesn't clutter the Mac:

- **Kept (Application Support):** the notes, the frames and pictures they show, and assistant chats. Removed with the note or chat.
- **Made again when needed (Caches, temporary folder):** the search index, the speech model compiled for this Mac, and working files. macOS may clear these when space runs low.
- **Cleaned up on its own:** frames of deleted notes, temporary files older than a day, unreadable stores set aside more than 30 days ago, and speech model builds left behind by OS updates.
- **Never copied:** your videos, audio and pictures stay where they are; notes point to them.

Settings › Storage shows what each part takes, and clears the caches or the speech model build.

## How it works

| Step | Engine | Where it comes from |
|------|--------|---------------------|
| Speech | Whisper large-v3 turbo (WhisperKit, Core ML) | Bundled in the app (about 650 MB) |
| Speech fallback | Apple SpeechAnalyzer | Built into macOS |
| Music and singing | Apple SoundAnalysis classifier | Built into macOS |
| On-screen text | Apple Vision text recognition | Built into macOS |
| Text in pictures | Apple Vision document recognition | Built into macOS |
| Title, summary, headings | Apple Foundation Models | Built into macOS (Apple Intelligence) |
| Search | SQLite FTS5 full-text index, NaturalLanguage sentence embeddings | Built into macOS |

- **Speech:** Automatic mode uses Whisper first (most accurate, about 100 languages, detects the language), then Apple Speech if Whisper can't run. Settings can put Apple Speech first.
- **Music:** the soundtrack is classified in 3-second windows. Singing, or music with little talking, is silenced before Whisper runs and left out of the transcript; the note marks where it played. Talking over background music is still transcribed. Settings can turn this off.
- **On-screen text:** frames are sampled every second (every 2 to 3 seconds for long videos) and unchanged frames are skipped. `ScreenTextSorter` then sorts the text:
  - text on screen in most frames is a watermark (handles, app marks, web addresses, tiny print; dropped) or, if it's a line or two, a title shown once at the top. More unchanging text is the video's content and stays a slide;
  - short text that changes along with the speech, and accounts for most of what's said while it shows, is a subtitle. The transcript is kept, except where the speech engine was unsure (low confidence) or missed words, or heard nothing while the sound classifier hears talking; there the subtitles are used;
  - without speech, short text that keeps changing in one place is the captions, and becomes the note's text;
  - everything else is grouped into moments: slides (with a frame grab) and remarks (a line or two that isn't said).
- **Pictures:** each picture is read with Vision's document reader, which keeps paragraphs, lists, and tables.
- **Formatting:** off until it's turned on in Settings › Formatting. The language model only writes the title, summary, key points, and headings. The transcript is never reworded. When it's off, or without Apple Intelligence, notes still get slide titles as headings and a title from the opening slide or the file name.

## Performance

Measured on the dev Mac with `./scripts/build.sh bench`, on about 3 minutes of speech:

| Whisper runs on | First-ever load | Later loads | Transcription |
|-----------------|-----------------|-------------|---------------|
| Neural Engine | 300 s (one-time compile) | 4 s | 14x real time (4 chunks at a time; 11x one at a time) |
| Hybrid: GPU encoder, Neural Engine decoder | about 50 s | 4 s | 4.5x real time |
| GPU | 47 s | 3 s | 2.8x real time |

The Neural Engine is the fastest and uses the least power, but the first time a Mac loads the model, Core ML compiles it for that Mac's Neural Engine. Apple doesn't let apps ship that compiled form, and it's cached per model location and OS version. `WhisperService` handles this:

- **Nothing loads at launch.** The model loads when you add a video (or reopen the app with videos still waiting), so the app opens light and nothing is compiled until it's needed.
- **First video:** the hybrid loads first, so the video transcribes after about a minute (66 s measured from a cold start), while the Neural Engine compiles in the background (about 6 minutes). Then every video uses the Neural Engine and the hybrid is unloaded.
- **Later videos:** the Neural Engine loads directly (about 5 to 12 s). If Core ML dropped its cache (after an OS update, for example), the hybrid takes over after 8 seconds and the compile runs again in the background.
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

The test fixtures are three narrated slides with a burned-in caption (and the same narration as audio only), narration with matching subtitles over quiet music, a sung song with captions, captions with no sound, and two pictures. They aren't in the repository because most use a macOS system voice, which Apple's license doesn't allow sharing publicly, so the script makes them on your Mac. `./scripts/build.sh test -only-testing:OvylTests/SnapshotTests` renders the main screens offscreen; the PNGs are printed into `.build/main/build.log` as `SNAPSHOT <name> <base64>` lines, since the app container is private.

## Layout

- `Ovyl/Pipeline`: audio decoding, music detection, Whisper and Apple Speech engines, on-screen text reader and sorter, picture reader, note composer, smart formatter.
- `Ovyl/Index`: the search index (passages by words and by meaning) and the indexer that keeps it in step with the notes.
- `Ovyl/Assistant`: chats, the library tools the assistant works through, and the Claude client.
- `Ovyl/Model`: the SwiftData `Note` and `Folder`, the note's JSON content, and its Markdown: written, parsed and exported.
- `Ovyl/UI`: SwiftUI views: the sidebar, notes list, note page, media pane, frames grid, media viewer and info panes, the Markdown reader and editor in `Ovyl/UI/Markdown`, and the logo and its motions in `Ovyl/UI/Logo`.
- `OvylTests`: Swift Testing unit tests, `PipelineIntegrationTests`, the index and tools in `LibraryTests`, and the assistant with the on-device model in `AssistantTests`.

## Credits

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax (MIT) runs Whisper with Core ML.
- The lecture photo in the empty states is by [Vitaly Gariev](https://unsplash.com/@silverkblack) on [Unsplash](https://unsplash.com/photos/nrE0LK_qN7E), under the Unsplash License.
- [Caveat](https://github.com/googlefonts/caveat) by Impallari Type (SIL Open Font License 1.1) is the handwriting in the empty states; its license is in `Ovyl/Resources/Fonts`.
- [Whisper](https://github.com/openai/whisper) by OpenAI; the Core ML conversion is [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) (MIT) and the tokenizer comes from [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3) (Apache 2.0). Both are downloaded by `scripts/fetch-models.sh`, not stored here.

## License

Ovyl is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You may use, study and change it for any non-commercial purpose. Selling it, or using it in
anything that earns money, is not allowed. The first published version, released under MIT, remains under MIT.

The Ovyl name and icon are not covered by the license: a modified version must use its own
name and icon.
