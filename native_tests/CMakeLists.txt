# Tests de la couche native sur l'ordinateur (pas sur Android).
# Usage : cmake -S native_tests -B build-native && cmake --build build-native && ctest --test-dir build-native
cmake_minimum_required(VERSION 3.16)
project(andika_native_tests LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

get_filename_component(ANDIKA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(WHISPER_DIR "${ANDIKA_ROOT}/third_party/whisper.cpp")
set(SHIM_DIR "${ANDIKA_ROOT}/android/app/src/main/cpp")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)
add_subdirectory("${WHISPER_DIR}" whisper_build)

add_executable(test_andika test_andika.cpp "${SHIM_DIR}/andika_whisper.cpp")
target_include_directories(test_andika PRIVATE "${SHIM_DIR}" "${WHISPER_DIR}/include" "${WHISPER_DIR}/ggml/include")
target_link_libraries(test_andika PRIVATE whisper)
target_compile_definitions(test_andika PRIVATE
  ANDIKA_TEST_MODEL="${WHISPER_DIR}/models/for-tests-ggml-tiny.bin"
  ANDIKA_TEST_WAV="${WHISPER_DIR}/samples/jfk.wav")

enable_testing()
add_test(NAME andika_native COMMAND test_andika)
