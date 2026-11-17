cmake_minimum_required(VERSION 3.22.1)
project(andika_whisper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Racine du dépôt : android/app/src/main/cpp -> 5 niveaux au-dessus.
get_filename_component(ANDIKA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
set(WHISPER_DIR "${ANDIKA_ROOT}/third_party/whisper.cpp")

if(NOT EXISTS "${WHISPER_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "whisper.cpp est absent. Lancez : git submodule update --init --recursive")
endif()

# Options de whisper.cpp / ggml adaptées à un téléphone.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)    # pas d'optimisation propre à la machine de compilation
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)

add_subdirectory("${WHISPER_DIR}" whisper_build)

add_library(andika_whisper SHARED andika_whisper.cpp)
target_include_directories(andika_whisper PRIVATE
  "${WHISPER_DIR}/include"
  "${WHISPER_DIR}/ggml/include")
target_link_libraries(andika_whisper PRIVATE whisper)
set_target_properties(andika_whisper PROPERTIES CXX_VISIBILITY_PRESET hidden)

if(ANDROID)
  target_link_libraries(andika_whisper PRIVATE log)
  # Pages mémoire de 16 Ko (exigence de Google Play pour Android 15 et plus).
  target_link_options(andika_whisper PRIVATE "-Wl,-z,max-page-size=16384")
endif()
