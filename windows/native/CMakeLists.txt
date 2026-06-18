cmake_minimum_required(VERSION 3.24)
project(TypeSpeakerNativeASRWindows C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(NOT DEFINED SHERPA_ONNX_ROOT)
  message(FATAL_ERROR "Set SHERPA_ONNX_ROOT to the sherpa-onnx Windows package directory")
endif()

add_library(TypeSpeakerNativeASR SHARED
  ../../native/TypeSpeakerNativeASR.c
)

target_include_directories(TypeSpeakerNativeASR PRIVATE
  ../../native
  "${SHERPA_ONNX_ROOT}/include"
)

target_link_directories(TypeSpeakerNativeASR PRIVATE
  "${SHERPA_ONNX_ROOT}/lib"
)

target_link_libraries(TypeSpeakerNativeASR PRIVATE
  sherpa-onnx-c-api
)

target_compile_definitions(TypeSpeakerNativeASR PRIVATE
  _CRT_SECURE_NO_WARNINGS
  _CRT_NONSTDC_NO_DEPRECATE
)

if(MSVC)
  target_compile_options(TypeSpeakerNativeASR PRIVATE /utf-8)
endif()
