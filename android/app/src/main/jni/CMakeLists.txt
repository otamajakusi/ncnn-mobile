project(yolov5ncnn)

cmake_minimum_required(VERSION 3.4.1)

set(ncnn_DIR ${CMAKE_SOURCE_DIR}/ncnn-20221128-android-vulkan/${ANDROID_ABI}/lib/cmake/ncnn)
find_package(ncnn REQUIRED)

add_library(yolov5ncnn SHARED yolov5ncnn_jni.cpp)

include_directories(eigen)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")
include_directories(ByteTrack-cpp/include)
add_library(bytetrack
    SHARED
    ByteTrack-cpp/src/BYTETracker.cpp
    ByteTrack-cpp/src/KalmanFilter.cpp
    ByteTrack-cpp/src/Object.cpp
    ByteTrack-cpp/src/Rect.cpp
    ByteTrack-cpp/src/STrack.cpp
    ByteTrack-cpp/src/lapjv.cpp)

target_link_libraries(yolov5ncnn
    ncnn
    bytetrack

    jnigraphics
)
