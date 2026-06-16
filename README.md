# 🎵 Tales Lyrics Plugin

Offline, AI-powered synced lyrics for the **Tales music player** — powered by [Whisper](https://github.com/openai/whisper) running fully on-device.

No internet needed after the one-time plugin download. Word-level and line-level LRC supported.

---

## Features

| Feature | Details |
|---|---|
| 🔍 Lyrics resolution | Embedded ID3 tags → sidecar `.lrc` → disk cache → AI generation |
| 🤖 AI transcription | OpenAI Whisper `base` model via native JNI bridge |
| 📶 Offline | Works 100% offline after initial plugin download |
| 🔤 Word highlighting | Per-word karaoke-style sync for word-level LRC files |
| 📦 Runtime plugin | Native `.so` and model weights are **never** bundled in the APK — downloaded on demand |

---

## Architecture

```
LyricsProvider (ChangeNotifier)
    │
    ├── LyricsService          ← resolution pipeline
    │       ├── ID3 tags       (flutter_audio_tagger)
    │       ├── .lrc sidecar   (file system)
    │       ├── LRC cache      (disk)
    │       └── WhisperBridge  ← MethodChannel → WhisperPlugin.kt
    │
    ├── LyricsPackManager      ← download, extract, cache management
    │
    └── LyricsModel            ← LRC parser + active line/word helpers

LyricsScreen                  ← UI: all states, word/line highlighting
AudioVisualizer               ← animated waveform background
LyricsSyncController          ← position stream → (line, word) stream
```

---

## Plugin Bundle Layout

The plugin is distributed as a GitHub Release zip per ABI:

```
lyrics_plugin_v1_arm64.zip
  ├── libwhisper_jni.so       # arm64-v8a native JNI bridge (~5 MB)
  ├── ggml-base.bin           # Whisper base weights (~142 MB)
  └── plugin_manifest.json   # { "version": "1.0.0", "model": "base", "abi": "arm64-v8a" }

lyrics_plugin_v1_x86_64.zip
  ├── libwhisper_jni.so       # x86_64 native JNI bridge (~5 MB)
  ├── ggml-base.bin           # same weights, ABI-independent
  └── plugin_manifest.json   # { "version": "1.0.0", "model": "base", "abi": "x86_64" }
```

Files are installed to `<appDocuments>/lyrics_pack/` at runtime. **Nothing is added to the APK.**

---

## Integration

### 1. pubspec.yaml

```yaml
dependencies:
  dio: ^5.4.0
  archive: ^3.4.10
  path_provider: ^2.1.2
  flutter_audio_tagger: ^2.0.3
  provider: ^6.1.2
```

### 2. main.dart

```dart
import 'lyrics/lyrics_provider.dart';

MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => LyricsProvider()),
    // ... other providers
  ],
  child: MyApp(),
)
```

### 3. MainActivity.kt

```kotlin
import com.talesapp.lyrics.LyricsPluginRegistrar

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    LyricsPluginRegistrar.register(flutterEngine)
}
```

### 4. android/app/build.gradle

```groovy
android {
    defaultConfig {
        ndk {
            abiFilters "arm64-v8a", "x86_64"
        }
    }
}
```

> ⚠️ Do **NOT** add `.so` files to `jniLibs`. They are loaded at runtime from the documents directory.

---

## Usage

### Toggle lyrics for the current song

```dart
await context.read<LyricsProvider>().toggleLyrics(
  audioPath: '/path/to/song.mp3',
  songId:    'unique-song-id',
);
```

### Notify on song change

```dart
await context.read<LyricsProvider>().onSongChanged(
  audioPath: newPath,
  songId:    newSongId,
);
```

### Sync playback position

```dart
// Call this from your position stream listener
context.read<LyricsProvider>().onPosition(currentPosition);
```

### Show the lyrics screen

```dart
LyricsScreen(
  positionStream: audioPlayer.positionStream,
  isDark:         Theme.of(context).brightness == Brightness.dark,
)
```

---

## Building the Native Plugin

See [`docs/BUILD_NATIVE.md`](docs/BUILD_NATIVE.md) for instructions on compiling `libwhisper_jni.so` for each ABI and packaging the GitHub Release zips.

---

## License

MIT — see [LICENSE](LICENSE)
