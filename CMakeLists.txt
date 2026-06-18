cmake_minimum_required(VERSION 3.22)
project(whisper_jni)

add_library(whisper_jni SHARED native/whisper_jni.cpp)

target_include_directories(whisper_jni PRIVATE
    ${CMAKE_SOURCE_DIR}/vendor/whisper.cpp/include
    ${CMAKE_SOURCE_DIR}/vendor/whisper.cpp/ggml/include
    ${CMAKE_SOURCE_DIR}/native
)

# ── Declare libwhisper.so as an imported shared lib ───────────────────────────
# The .so must exist at this path when cmake runs (downloaded by the parent job).
add_library(whisper SHARED IMPORTED)
set_target_properties(whisper PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI}/libwhisper.so
)

find_library(log-lib   log)
find_library(android-lib android)

target_link_libraries(whisper_jni
    whisper          # resolves all whisper_* symbols at link time
    ${log-lib}
    ${android-lib}
)

set_target_properties(whisper_jni PROPERTIES
    OUTPUT_NAME    "whisper_jni"
    ANDROID_STL    c++_shared
)
