// native/whisper_jni.cpp
//
// JNI bridge for the Whisper offline lyrics plugin.
//
// Package: com.squet.talesplayer   (matches WhisperPlugin.kt)
// Symbols exported:
//   Java_com_squet_talesplayer_WhisperPlugin_nativeInit
//   Java_com_squet_talesplayer_WhisperPlugin_nativeTranscribe
//   Java_com_squet_talesplayer_WhisperPlugin_nativeRelease

// ── dr_libs: header-only audio decoders ──────────────────────────────────────
// The IMPLEMENTATION macros MUST be defined before the first #include of each
// header, and those includes must be at file scope (not inside a function).
// Defining them inside a function body — as the previous version did — means
// the preprocessor has already finished parsing the header declarations by the
// time the macro is set, so the type/function definitions never get emitted and
// the compiler sees only forward declarations → "unknown type name drwav_uint16".
#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"

#define DR_MP3_IMPLEMENTATION
#include "dr_mp3.h"

#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
// ─────────────────────────────────────────────────────────────────────────────

#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <sstream>
#include <cstdio>

#include "whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Global context (one model loaded at a time) ───────────────────────────────
static whisper_context* g_ctx = nullptr;

// ── LRC timestamp formatter ───────────────────────────────────────────────────
// Whisper timestamps are in units of 10 ms (centiseconds).
static std::string formatLrcTimestamp(int64_t t) {
    int total_cs = (int)t;
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
    jobject   callback;
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

    jfloat jProgress = static_cast<jfloat>(progress / 100.0f);
    char msg[32];
    snprintf(msg, sizeof(msg), "Transcribing... %d%%", progress);
    jstring jMsg = data->env->NewStringUTF(msg);
    data->env->CallVoidMethod(data->callback, data->invokeId, jProgress, jMsg);
    data->env->DeleteLocalRef(jMsg);
}

// ── Audio loader: WAV / MP3 / FLAC → mono float32 @ 16 kHz ──────────────────
// Returns false if no format could decode the file.
static bool loadAudioFile(
    const char*          path,
    std::vector<float>&  out
) {
    // WAV
    {
        drwav wav;
        if (drwav_init_file(&wav, path, nullptr)) {
            drwav_uint64 total = wav.totalPCMFrameCount;
            uint32_t     ch   = wav.channels;
            std::vector<float> tmp(total * ch);
            drwav_uint64 read = drwav_read_pcm_frames_f32(&wav, total, tmp.data());
            drwav_uninit(&wav);
            out.resize(read);
            for (drwav_uint64 i = 0; i < read; i++) {
                float s = 0.0f;
                for (uint32_t c = 0; c < ch; c++) s += tmp[i * ch + c];
                out[i] = s / ch;
            }
            return true;
        }
    }
    // MP3
    {
        drmp3 mp3;
        if (drmp3_init_file(&mp3, path, nullptr)) {
            drmp3_uint64 total = drmp3_get_pcm_frame_count(&mp3);
            uint32_t     ch   = mp3.channels;
            std::vector<float> tmp(total * ch);
            drmp3_uint64 read = drmp3_read_pcm_frames_f32(&mp3, total, tmp.data());
            drmp3_uninit(&mp3);
            out.resize(read);
            for (drmp3_uint64 i = 0; i < read; i++) {
                float s = 0.0f;
                for (uint32_t c = 0; c < ch; c++) s += tmp[i * ch + c];
                out[i] = s / ch;
            }
            return true;
        }
    }
    // FLAC
    {
        drflac* flac = drflac_open_file(path, nullptr);
        if (flac) {
            drflac_uint64 total = flac->totalPCMFrameCount;
            uint32_t      ch   = flac->channels;
            std::vector<float> tmp(total * ch);
            drflac_uint64 read = drflac_read_pcm_frames_f32(flac, total, tmp.data());
            drflac_close(flac);
            out.resize(read);
            for (drflac_uint64 i = 0; i < read; i++) {
                float s = 0.0f;
                for (uint32_t c = 0; c < ch; c++) s += tmp[i * ch + c];
                out[i] = s / ch;
            }
            return true;
        }
    }
    return false;
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

    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;

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
    jobject progressCallback
) {
    if (!g_ctx) {
        jclass exc = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exc, "Model not initialised");
        return nullptr;
    }

    const char* audioPath = env->GetStringUTFChars(audioPathJ, nullptr);
    LOGI("Transcribing: %s", audioPath);

    // ── Decode audio ──────────────────────────────────────────────────────────
    std::vector<float> pcmf32;
    bool loaded = loadAudioFile(audioPath, pcmf32);
    env->ReleaseStringUTFChars(audioPathJ, audioPath);

    if (!loaded || pcmf32.empty()) {
        jclass exc = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exc, "Audio decode failed or produced no samples");
        return nullptr;
    }

    // ── Whisper params ────────────────────────────────────────────────────────
    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress       = false;
    wparams.print_special        = false;
    wparams.print_realtime       = false;
    wparams.print_timestamps     = true;
    wparams.translate            = false;
    wparams.language             = "auto";
    wparams.n_threads            = 4;
    wparams.single_segment       = false;
    wparams.max_tokens           = 0;
    wparams.token_timestamps     = true;

    // ── Progress callback ─────────────────────────────────────────────────────
    ProgressCallbackData cbData;
    cbData.env      = env;
    cbData.callback = progressCallback;
    cbData.invokeId = nullptr;

    if (progressCallback) {
        jclass cbClass  = env->GetObjectClass(progressCallback);
        cbData.invokeId = env->GetMethodID(
            cbClass, "invoke",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        );
        env->DeleteLocalRef(cbClass);
        if (cbData.invokeId) {
            wparams.progress_callback           = whisperProgressCallback;
            wparams.progress_callback_user_data = &cbData;
        }
    }

    // ── Run Whisper ───────────────────────────────────────────────────────────
    int rc = whisper_full(g_ctx, wparams, pcmf32.data(), (int)pcmf32.size());
    if (rc != 0) {
        jclass exc = env->FindClass("java/lang/RuntimeException");
        char msg[64];
        snprintf(msg, sizeof(msg), "whisper_full failed with code %d", rc);
        env->ThrowNew(exc, msg);
        return nullptr;
    }

    // ── Build LRC output ──────────────────────────────────────────────────────
    std::ostringstream lrc;
    int nSegments = whisper_full_n_segments(g_ctx);

    for (int s = 0; s < nSegments; s++) {
        int nTokens = whisper_full_n_tokens(g_ctx, s);

        if (nTokens > 1) {
            // Word-level: one <timestamp>word per token
            for (int t = 0; t < nTokens; t++) {
                whisper_token_data td = whisper_full_get_token_data(g_ctx, s, t);
                if (td.id >= whisper_token_eot(g_ctx)) continue;
                const char* text = whisper_full_get_token_text(g_ctx, s, t);
                if (!text || text[0] == '\0') continue;
                lrc << "<" << formatLrcTimestamp(td.t0) << ">" << text;
            }
            lrc << "\n";
        } else {
            // Segment-level fallback
            int64_t     t0   = whisper_full_get_segment_t0(g_ctx, s);
            const char* text = whisper_full_get_segment_text(g_ctx, s);
            if (text) lrc << "[" << formatLrcTimestamp(t0) << "]" << text << "\n";
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
