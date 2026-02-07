cmake_minimum_required(VERSION 3.10)

project(whisper_flutter_library LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 20)

# Optimization flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -fdata-sections -ffunction-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fdata-sections -ffunction-sections")

# Include directories
include_directories(json)
include_directories(src)
include_directories(src/include)
include_directories(src/src)
include_directories(src/ggml/include)
include_directories(src/ggml/src)
include_directories(src/ggml/src/ggml-cpu)

# Collect all engine source files
file(GLOB_RECURSE WHISPER_SRC CONFIGURE_DEPENDS
    src/src/*.cpp
    src/src/*.c
    src/ggml/src/*.cpp
    src/ggml/src/*.c
)

add_library(whisper ${WHISPER_SRC})

# Enable CPU backend (required for ggml_backend_dev_by_type to return a valid CPU device)
target_compile_definitions(whisper PRIVATE GGML_USE_CPU)

# Some upstream sources expect WHISPER_VERSION / GGML_VERSION / GGML_COMMIT.
# The packaged header defines these, but not all translation units include it,
# so force-include it for this target.
target_compile_options(whisper PRIVATE -include whisper-version.h)

if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    target_compile_options(whisper PRIVATE -march=armv8.2-a+fp16)
elseif (${ANDROID_ABI} STREQUAL "armeabi-v7a")
    target_compile_options(whisper PRIVATE -mfpu=neon-vfpv4)
endif ()

# Main bridge library
add_library(whisper_flutter SHARED main.cpp)
target_link_libraries(whisper_flutter PRIVATE whisper log)
target_link_options(whisper_flutter PRIVATE -Wl,-u,request)
target_compile_definitions(whisper_flutter PUBLIC DART_SHARED_LIB)

set_target_properties(whisper_flutter PROPERTIES
  PUBLIC_HEADER src/whisper.h 
  OUTPUT_NAME "whisper"
)
