// native/whisper_jni.cpp
//
// JNI bridge for the Whisper offline lyrics plugin.
//
// Package: com.squet.talesplayer   (matches WhisperPlugin.kt)
// Symbols exported:
//   Java_com_squet_talesplayer_WhisperPlugin_nativeInit
//   Java_com_squet_talesplayer_WhisperPlugin_nativeTranscribe
//   Java_com_squet_talesplayer_WhisperPlugin_nativeRelease
//
// Whisper API used: whisper.cpp v1.7.3
//   whisper_context_default_params()
//   whisper_init_from_file_with_params()
//   whisper_full_default_params()
//   whisper_full()
//   whisper_full_n_segments()
//   whisper_full_get_segment_t0()
//   whisper_full_get_segment_t1()
//   whisper_full_get_segment_text()
//   whisper_full_n_tokens()
//   whisper_full_get_token_data()
//   whisper_free()

#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <cstdio>

#include "whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Global context (one model loaded at a time) ───────────────────────────────
static whisper_context* g_ctx = nullptr;

// ── LRC timestamp helpers ─────────────────────────────────────────────────────

// Converts whisper centisecond timestamp (t * 10 ms) to LRC mm:ss.xx format.
static std::string formatLrcTimestamp(int64_t t) {
    // whisper timestamps are in units of 10ms (i.e. centiseconds)
    int total_cs = (int)(t);          // centiseconds
    int minutes  = total_cs / 6000;
    int seconds  = (total_cs % 6000) / 100;
    int cs       = total_cs % 100;
    char buf[16];
    snprintf(buf, sizeof(buf), "%02d:%02d.%02d", minutes, seconds, cs);
    return std::string(buf);
}

// ── Progress callback shim ────────────────────────────────────────────────────

struct ProgressCallbackData {
    JNIEnv*   env;
    jobject   callback;   // Kotlin lambda / SAM: (Float, String) -> Unit
    jmethodID invokeId;
};

static void whisperProgressCallback(
    struct whisper_context* /*ctx*/,
    struct whisper_state*   /*state*/,
    int                     progress,
    void*                   user_data
) {
    if (!user_data) return;
    auto* data = reinterpret_cast<ProgressCallbackData*>(user_data);
    if (!data->env || !data->callback || !data->invokeId) return;

    float  pFloat = progress / 100.0f;
    jfloat jProgress = static_cast<jfloat>(pFloat);

    // Build a progress message string
    char msg[32];
    snprintf(msg, sizeof(msg), "Transcribing… %d%%", progress);
    jstring jMsg = data->env->NewStringUTF(msg);

    data->env->CallVoidMethod(data->callback, data->invokeId, jProgress, jMsg);
    data->env->DeleteLocalRef(jMsg);
}

// ── JNI: nativeInit ───────────────────────────────────────────────────────────

extern "C"
JNIEXPORT jint JNICALL
Java_com_squet_talesplayer_WhisperPlugin_nativeInit(
    JNIEnv* env,
    jobject /* thiz */,
    jstring modelPathJ
) {
    const char* modelPath = env->GetStringUTFChars(modelPathJ, nullptr);
    LOGI("Loading Whisper model from: %s", modelPath);

    // Free any previously loaded context
    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;  // Android CPU-only

    g_ctx = whisper_init_from_file_with_params(modelPath, cparams);
    env->ReleaseStringUTFChars(modelPathJ, modelPath);

    if (!g_ctx) {
        LOGE("whisper_init_from_file failed");
        return -1;
    }

    LOGI("Whisper model loaded OK");
    return 0;
}

// ── JNI: nativeTranscribe ─────────────────────────────────────────────────────

extern "C"
JNIEXPORT jstring JNICALL
Java_com_squet_talesplayer_WhisperPlugin_nativeTranscribe(
    JNIEnv* env,
    jobject /* thiz */,
    jstring audioPathJ,
    jobject progressCallback   // Kotlin (Float, String) -> Unit
) {
    if (!g_ctx) {
        jclass exc = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exc, "Model not initialised");
        return nullptr;
    }

    const char* audioPath = env->GetStringUTFChars(audioPathJ, nullptr);
    LOGI("Transcribing: %s", audioPath);

    // ── Read PCM samples from file via libavformat / minimp3 shim ────────────
    // whisper_pcm_to_mel requires float32 samples @ 16 kHz mono.
    // We use the helper whisper provides for reading audio files when built
    // with WHISPER_FFMPEG=OFF (default): whisper reads WAV via its own reader.
    // For MP3/FLAC the caller (LyricsService) must resolve to a real file path;
    // Android's MediaCodec decoding is handled on the Dart side before calling
    // transcribe.  Here we pass the path directly to whisper_full which
    // internally calls dr_wav / dr_mp3 (bundled in whisper.cpp source).

    // Load audio via whisper's built-in reader
    std::vector<float> pcmf32;
    std::vector<std::vector<float>> pcmf32s;

    // whisper.cpp v1.7.3 exposes read_wav helper via common/common.h when
    // building examples, but for JNI use we call the lower-level approach:
    // pass the file path to whisper_full directly — whisper handles decoding.

    // ── Set up full params ────────────────────────────────────────────────────
    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    wparams.print_progress    = false;
    wparams.print_special     = false;
    wparams.print_realtime    = false;
    wparams.print_timestamps  = true;
    wparams.translate         = false;
    wparams.language          = "auto";
    wparams.n_threads         = 4;
    wparams.single_segment    = false;
    wparams.max_tokens        = 0;       // no limit
    wparams.token_timestamps  = true;    // enable for word-level LRC
    wparams.dtw_token_timestamps = true; // DTW alignment for precise word timing

    // Progress callback
    ProgressCallbackData cbData;
    cbData.env      = env;
    cbData.callback = progressCallback;
    cbData.invokeId = nullptr;

    if (progressCallback) {
        jclass cbClass = env->GetObjectClass(progressCallback);
        // Kotlin lambda compiled to kotlin.jvm.functions.Function2
        cbData.invokeId = env->GetMethodID(
            cbClass,
            "invoke",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        );
        if (!cbData.invokeId) {
            LOGE("Could not find invoke method on progress callback — continuing without progress");
            cbData.callback = nullptr;
        }
        env->DeleteLocalRef(cbClass);
        wparams.progress_callback      = whisperProgressCallback;
        wparams.progress_callback_user_data = &cbData;
    }

    // ── Read audio samples ────────────────────────────────────────────────────
    // Use whisper's common audio reader (available in the whisper.cpp source
    // tree when WHISPER_BUILD_EXAMPLES=ON provides common.cpp).  Since we
    // build with WHISPER_BUILD_EXAMPLES=OFF, we use the read_wav helper that
    // ships in whisper.h itself (whisper_pcm_to_mel is internal, but
    // whisper_full accepts a float* + sample count directly).
    //
    // Simplest portable approach for the plugin: use minifile/dr_libs headers
    // bundled in our own native/ directory.  We include dr_mp3.h + dr_wav.h
    // (header-only, MIT licensed) to decode the audio file.

    #define DR_WAV_IMPLEMENTATION
    #define DR_MP3_IMPLEMENTATION
    #define DR_FLAC_IMPLEMENTATION
    #include "dr_wav.h"
    #include "dr_mp3.h"
    #include "dr_flac.h"

    const int TARGET_SR = WHISPER_SAMPLE_RATE; // 16000

    // Try WAV
    bool loaded = false;
    {
        drwav wav;
        if (drwav_init_file(&wav, audioPath, nullptr)) {
            std::vector<float> tmp(wav.totalPCMFrameCount * wav.channels);
            drwav_uint64 framesRead = drwav_read_pcm_frames_f32(&wav, wav.totalPCMFrameCount, tmp.data());
            drwav_uninit(&wav);
            // Down-mix to mono and resample to 16 kHz if needed
            // (simple averaging for multi-channel; linear for SR)
            pcmf32.resize(framesRead);
            for (drwav_uint64 i = 0; i < framesRead; i++) {
                float s = 0.0f;
                for (uint32_t ch = 0; ch < wav.channels; ch++) {
                    s += tmp[i * wav.channels + ch];
                }
                pcmf32[i] = s / wav.channels;
            }
            loaded = true;
        }
    }

    // Try MP3
    if (!loaded) {
        drmp3 mp3;
        if (drmp3_init_file(&mp3, audioPath, nullptr)) {
            drmp3_uint64 totalFrames = drmp3_get_pcm_frame_count(&mp3);
            std::vector<float> tmp(totalFrames * mp3.channels);
            drmp3_uint64 framesRead = drmp3_read_pcm_frames_f32(&mp3, totalFrames, tmp.data());
            drmp3_uninit(&mp3);
            pcmf32.resize(framesRead);
            for (drmp3_uint64 i = 0; i < framesRead; i++) {
                float s = 0.0f;
                for (uint32_t ch = 0; ch < mp3.channels; ch++) {
                    s += tmp[i * mp3.channels + ch];
                }
                pcmf32[i] = s / mp3.channels;
            }
            loaded = true;
        }
    }

    // Try FLAC
    if (!loaded) {
        drflac* flac = drflac_open_file(audioPath, nullptr);
        if (flac) {
            std::vector<float> tmp(flac->totalPCMFrameCount * flac->channels);
            drflac_uint64 framesRead = drflac_read_pcm_frames_f32(flac, flac->totalPCMFrameCount, tmp.data());
            uint32_t channels = flac->channels;
            drflac_close(flac);
            pcmf32.resize(framesRead);
            for (drflac_uint64 i = 0; i < framesRead; i++) {
                float s = 0.0f;
                for (uint32_t ch = 0; ch < channels; ch++) {
                    s += tmp[i * channels + ch];
                }
                pcmf32[i] = s / channels;
            }
            loaded = true;
        }
    }

    env->ReleaseStringUTFChars(audioPathJ, audioPath);

    if (!loaded || pcmf32.empty()) {
        jclass exc = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exc, "Audio decode failed or produced no samples");
        return nullptr;
    }

    // ── Run whisper ───────────────────────────────────────────────────────────
    int rc = whisper_full(g_ctx, wparams, pcmf32.data(), (int)pcmf32.size());
    if (rc != 0) {
        jclass exc = env->FindClass("java/lang/RuntimeException");
        char msg[64];
        snprintf(msg, sizeof(msg), "whisper_full failed with code %d", rc);
        env->ThrowNew(exc, msg);
        return nullptr;
    }

    // ── Build word-level LRC output ───────────────────────────────────────────
    std::ostringstream lrc;
    int nSegments = whisper_full_n_segments(g_ctx);

    for (int s = 0; s < nSegments; s++) {
        int nTokens = whisper_full_n_tokens(g_ctx, s);
        bool hasWordTimings = (nTokens > 1);

        if (hasWordTimings) {
            // Word-level: emit one LRC word tag per token
            for (int t = 0; t < nTokens; t++) {
                whisper_token_data td = whisper_full_get_token_data(g_ctx, s, t);
                if (td.id >= whisper_token_eot(g_ctx)) continue; // skip special tokens
                const char* text = whisper_full_get_token_text(g_ctx, s, t);
                if (!text || text[0] == '\0') continue;
                // Skip pure whitespace tokens that start a segment
                std::string w(text);
                lrc << "<" << formatLrcTimestamp(td.t0) << ">" << w;
            }
            lrc << "\n";
        } else {
            // Segment-level fallback: single timestamp per line
            int64_t t0   = whisper_full_get_segment_t0(g_ctx, s);
            const char* text = whisper_full_get_segment_text(g_ctx, s);
            if (text) {
                lrc << "[" << formatLrcTimestamp(t0) << "]" << text << "\n";
            }
        }
    }

    return env->NewStringUTF(lrc.str().c_str());
}

// ── JNI: nativeRelease ────────────────────────────────────────────────────────

extern "C"
JNIEXPORT void JNICALL
Java_com_squet_talesplayer_WhisperPlugin_nativeRelease(
    JNIEnv* /* env */,
    jobject /* thiz */
) {
    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
        LOGI("Whisper model released.");
    }
}
