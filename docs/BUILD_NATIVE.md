# Building the Native Plugin

This doc explains how to compile `libwhisper_jni.so` manually if you need a local build (CI handles this automatically via the `release.yml` workflow).

## Prerequisites

- Android NDK r25c or later
- CMake 3.22+
- whisper.cpp submodule: `git submodule update --init --recursive`

## Build for arm64-v8a

```bash
cmake -B build_arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build_arm64 --target whisper_jni -j$(nproc)
# Output: build_arm64/libwhisper_jni.so
```

## Build for x86_64

```bash
cmake -B build_x86_64 \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=x86_64 \
  -DANDROID_PLATFORM=android-26 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build_x86_64 --target whisper_jni -j$(nproc)
# Output: build_x86_64/libwhisper_jni.so
```

## Download model weights

```bash
curl -L -o ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

## Package a release zip

```bash
# arm64
mkdir -p pkg_arm64
cp build_arm64/libwhisper_jni.so pkg_arm64/
cp ggml-base.bin pkg_arm64/
echo '{"version":"1.0.0","model":"base","abi":"arm64-v8a"}' > pkg_arm64/plugin_manifest.json
cd pkg_arm64 && zip ../lyrics_plugin_v1_arm64.zip * && cd ..

# x86_64
mkdir -p pkg_x86_64
cp build_x86_64/libwhisper_jni.so pkg_x86_64/
cp ggml-base.bin pkg_x86_64/
echo '{"version":"1.0.0","model":"base","abi":"x86_64"}' > pkg_x86_64/plugin_manifest.json
cd pkg_x86_64 && zip ../lyrics_plugin_v1_x86_64.zip * && cd ..
```

## Upload to GitHub Releases

Create a release tagged `lyrics-plugin-v1.0.0` and upload both zips as assets. The download URL in `LyricsPackManager` must match:

```
https://github.com/<YOUR_ORG>/<YOUR_REPO>/releases/download/lyrics-plugin-v1.0.0/lyrics_plugin_v1_arm64.zip
```

## Audio decoding note

`whisper_jni.cpp` currently has a `TODO` for PCM audio decoding. You need to decode the input audio to 16 kHz mono float32 before passing it to `whisper_full`. Options:

- **dr_wav** (header-only, for WAV files): [nothings/dr_libs](https://github.com/nothings/dr_libs)
- **FFmpeg via JNI**: full format support but adds significant size
- **Transcode on Dart side** before calling the channel: convert to WAV first using `ffmpeg_kit_flutter`
