cmake_minimum_required(VERSION 3.22)
project(whisper_jni)

# ── whisper_jni.so — built from our JNI source only ───────────────────────────
#
# libwhisper.so and the ggml stack are built separately by the parent job
# and are loaded via System.load() before this library.  We link against
# them as IMPORTED shared libraries so the build system knows the symbols
# are available at runtime without bundling them inside libwhisper_jni.so.

add_library(whisper_jni SHARED native/whisper_jni.cpp)

# Whisper headers — vendored whisper.cpp must be checked out before this runs
target_include_directories(whisper_jni PRIVATE
    ${CMAKE_SOURCE_DIR}/vendor/whisper.cpp/include
    ${CMAKE_SOURCE_DIR}/vendor/whisper.cpp/ggml/include
    ${CMAKE_SOURCE_DIR}/native                       # dr_wav.h / dr_mp3.h / dr_flac.h
)

# Android system libraries (always present in the device linker namespace)
find_library(log-lib  log)
find_library(android-lib android)

target_link_libraries(whisper_jni
    ${log-lib}
    ${android-lib}
    # whisper + ggml are loaded at runtime via System.load() —
    # declare as link-time stubs so the linker resolves symbols
    # without embedding them.  The actual .so files are not in jniLibs;
    # they live in the downloaded pack directory.
    -Wl,--allow-shlib-undefined
)

# Match ABI set in the parent CMake invocation
set_target_properties(whisper_jni PROPERTIES
    OUTPUT_NAME "whisper_jni"
    ANDROID_STL c++_shared
)
