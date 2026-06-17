cmake_minimum_required(VERSION 3.22)
project(whisper_jni VERSION 1.0.0)

# ── whisper.cpp ──────────────────────────────────────────────────────────────
add_subdirectory(vendor/whisper.cpp whisper_build EXCLUDE_FROM_ALL)

# ── JNI bridge ───────────────────────────────────────────────────────────────
add_library(
    whisper_jni
    SHARED
    android/src/main/kotlin/com/squet/talesplayer/lyrics/whisper/whisper_jni.cpp
)

target_include_directories(whisper_jni PRIVATE
    vendor/whisper.cpp
)

target_link_libraries(whisper_jni
    whisper
    android
    log
)

target_compile_options(whisper_jni PRIVATE
    $<$<CONFIG:Release>:-O3 -fvisibility=hidden>
)

set_target_properties(whisper_jni PROPERTIES
    OUTPUT_NAME "whisper_jni"
)
