# Minimum CMake version 3.25.2 for CUDA --std=c++20
cmake_minimum_required(VERSION 3.25.2...4.1.1 FATAL_ERROR)

# Optionaly set the version of flamegpu which should be used, ideally a tag (i.e. `v2.0.0-rc`) or branch name, or potentially a commit hash.
set(FLAMEGPU_VERSION "v2.0.0-rc.5" CACHE STRING "FLAMEGPU/FLAMEGPU2 git branch or tag to use")
# If the above version is a hash instead, also set FLAMEGPU_VERSION_ALLOW_HASH to ON
# set(FLAMEGPU_VERSION_ALLOW_HASH "ON")

# Manually specify the FLAMEGPU_VISUALISATION option to provide it prior to original configuration and allow the default to be overridden in the downstream project
option(FLAMEGPU_VISUALISATION "Enable FLAMEGPU visualisation support" OFF)

# Telemetry is off unless the user opts in (design: Constraints).
set(FLAMEGPU_SHARE_USAGE_STATISTICS OFF CACHE BOOL "Share usage statistics (telemetry) with the FLAME GPU team")

# Largest world the 1D macro properties hold; their sizes are compile-time template parameters.
set(SUGARSCAPE_MAX_CELLS 6250000 CACHE STRING "Largest width*height the macro properties hold (2500x2500)")

# Our core dependency is FLAMEGPU2 lib, first lets find it
include(${CMAKE_CURRENT_LIST_DIR}/cmake/flamegpu2.cmake)

# Handle CMAKE_CUDA_ARCHITECTURES gracefully, passign the project name for code-injection
include(${FLAMEGPU_ROOT}/cmake/CUDAArchitectures.cmake)
flamegpu_init_cuda_architectures(PROJECT sugarscape_gpu)

# Name the project and set languages, this must be done after flamegpu_init_cuda_architectures
project(sugarscape_gpu CUDA CXX)

# Include common rules from the FLAMEGPU/FLAMEGPU2 repositories CMake
include(${FLAMEGPU_ROOT}/cmake/common.cmake)

# Define output location of binary files
SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE}/)

# Manually list all of the files which require building or influence re-building (i.e. headers).
SET(ALL_SRC
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main.cu
    ${CMAKE_CURRENT_SOURCE_DIR}/src/config.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/config.cu
    ${CMAKE_CURRENT_SOURCE_DIR}/src/landscape_io.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/landscape_io.cu
    ${CMAKE_CURRENT_SOURCE_DIR}/src/model.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/model.cu
    ${CMAKE_CURRENT_SOURCE_DIR}/src/movement.cuh
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rules.cuh
    ${CMAKE_CURRENT_SOURCE_DIR}/src/host_state.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/host_state.cu
    ${CMAKE_CURRENT_SOURCE_DIR}/src/checks.cu
)

# Add the executable and set required flags for the target
flamegpu_add_executable("${PROJECT_NAME}" "${ALL_SRC}" "${FLAMEGPU_ROOT}" "${PROJECT_BINARY_DIR}" OFF)

# Add src directory to include path
target_include_directories("${PROJECT_NAME}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_compile_definitions("${PROJECT_NAME}" PRIVATE SUGARSCAPE_MAX_CELLS=${SUGARSCAPE_MAX_CELLS}u)

# Also set as (visual studio) startup project
set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" PROPERTY VS_STARTUP_PROJECT "${PROJECT_NAME}")

# Set the default (visual studio) debugger configuration
set_target_properties("${PROJECT_NAME}" PROPERTIES VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VS_DEBUGGER_COMMAND_ARGUMENTS "--help")
