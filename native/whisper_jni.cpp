/**
 * whisper_jni.cpp
 * JNI bridge between WhisperPlugin.kt and whisper.cpp
 */

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "whisper.h"

#define TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static whisper_context* g_ctx = nullptr;

// ── nativeInit ───────────────────────────────────────────────────────────────

extern "C" JNIEXPORT void JNICALL
Java_com_squet_talesplayer_lyrics_whisper_WhisperPlugin_nativeInit(
    JNIEnv* env, jobject /* thiz */, jstring modelPathJ)
{
    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }

    const char* modelPath = env->GetStringUTFChars(modelPathJ, nullptr);
    LOGI("Loading Whisper model from: %s", modelPath);

    whisper_context_params params = whisper_context_default_params();
    g_ctx = whisper_init_from_file_with_params(modelPath, params);

    env->ReleaseStringUTFChars(modelPathJ, modelPath);

    if (!g_ctx) {
        jclass ex = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(ex, "whisper_init_from_file failed");
    }
}

// ── nativeTranscribe ─────────────────────────────────────────────────────────

extern "C" JNIEXPORT jstring JNICALL
Java_com_squet_talesplayer_lyrics_whisper_WhisperPlugin_nativeTranscribe(
    JNIEnv* env, jobject /* thiz */,
    jstring audioPathJ,
    jobject /* onProgressCallback */)
{
    if (!g_ctx) {
        jclass ex = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(ex, "Model not initialised — call nativeInit first");
        return nullptr;
    }

    const char* audioPath = env->GetStringUTFChars(audioPathJ, nullptr);
    LOGI("Transcribing: %s", audioPath);

    // TODO: decode audioPath to 16kHz mono float32 PCM
    // Replace this with your audio decode implementation (dr_wav, ffmpeg, etc.)
    std::vector<float> pcm;

    env->ReleaseStringUTFChars(audioPathJ, audioPath);

    if (pcm.empty()) {
        jclass ex = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(ex, "Audio decode failed or produced no samples");
        return nullptr;
    }

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_realtime   = false;
    wparams.print_progress   = false;
    wparams.token_timestamps = true;
    wparams.language         = "auto";
    wparams.n_threads        = 4;

    int rc = whisper_full(g_ctx, wparams, pcm.data(), (int)pcm.size());
    if (rc != 0) {
        jclass ex = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(ex, "whisper_full failed");
        return nullptr;
    }

    // Build word-level LRC
    std::string lrc;
    int nSegments = whisper_full_n_segments(g_ctx);

    for (int s = 0; s < nSegments; s++) {
        int nTokens = whisper_full_n_tokens(g_ctx, s);
        for (int t = 0; t < nTokens; t++) {
            whisper_token_data td = whisper_full_get_token_data(g_ctx, s, t);
            const char* text = whisper_full_get_token_text(g_ctx, s, t);
            if (!text || text[0] == '\0') continue;

            int64_t ms = td.t0 * 10;
            int mm = (int)(ms / 60000);
            int ss = (int)((ms % 60000) / 1000);
            int cs = (int)((ms % 1000) / 10);

            char ts[32];
            snprintf(ts, sizeof(ts), "[%02d:%02d.%02d]", mm, ss, cs);
            lrc += ts;
            lrc += text;
        }
        lrc += '\n';
    }

    return env->NewStringUTF(lrc.c_str());
}

// ── nativeRelease ────────────────────────────────────────────────────────────

extern "C" JNIEXPORT void JNICALL
Java_com_squet_talesplayer_lyrics_whisper_WhisperPlugin_nativeRelease(
    JNIEnv* /* env */, jobject /* thiz */)
{
    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
        LOGI("Whisper model released.");
    }
}
