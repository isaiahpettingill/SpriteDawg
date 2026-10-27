cmake_minimum_required(VERSION 3.10)
project(spritedawg_avif_linux LANGUAGES C CXX)
set(PLUGIN_NAME "spritedawg_avif_linux_plugin")
add_library(${PLUGIN_NAME} SHARED "spritedawg_avif_linux_plugin.cc")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK)

find_program(CARGO_EXECUTABLE cargo REQUIRED)
set(RUST_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../rust")
set(RUST_TARGET "${CMAKE_CURRENT_BINARY_DIR}/native")
set(AVIF_LIBRARY "${RUST_TARGET}/release/libflutter_avif.so")
file(GLOB_RECURSE RUST_INPUTS "${RUST_SOURCE}/src/*.rs")
add_custom_command(OUTPUT "${AVIF_LIBRARY}"
  COMMAND "${CARGO_EXECUTABLE}" build --release --locked
    --manifest-path "${RUST_SOURCE}/Cargo.toml" --target-dir "${RUST_TARGET}"
  DEPENDS ${RUST_INPUTS} "${RUST_SOURCE}/Cargo.toml" "${RUST_SOURCE}/Cargo.lock"
  WORKING_DIRECTORY "${RUST_SOURCE}"
  COMMENT "Building offline-runtime AVIF codec for native Linux architecture"
  VERBATIM)
add_custom_target(spritedawg_avif_native DEPENDS "${AVIF_LIBRARY}")
add_dependencies(${PLUGIN_NAME} spritedawg_avif_native)
set(spritedawg_avif_linux_bundled_libraries "${AVIF_LIBRARY}" PARENT_SCOPE)
