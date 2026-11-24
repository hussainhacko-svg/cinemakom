# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(cinemakom LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cinemakom")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100)
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# Replace media_kit_libs_windows_video's 2023-09-24 libmpv-2.dll with a
# current build pinned by SHA256 (docs/PACKAGING.md §4). Keep this current:
# an FFmpeg or mpv security release means a Cinemakom release.
set(CINEMAKOM_LIBMPV_VERSION "20261111-git-bcde6b93cc")
set(CINEMAKOM_LIBMPV_ARCHIVE_NAME "mpv-dev-x86_64-${CINEMAKOM_LIBMPV_VERSION}.7z")
set(CINEMAKOM_LIBMPV_URL
  "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261111/${CINEMAKOM_LIBMPV_ARCHIVE_NAME}")
set(CINEMAKOM_LIBMPV_SHA256
  "273c079b11ea5575822f972756f4c9a71149a5c10130353abeb8586738938452")
set(CINEMAKOM_LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${CINEMAKOM_LIBMPV_ARCHIVE_NAME}")
set(CINEMAKOM_LIBMPV_DIR "${CMAKE_BINARY_DIR}/cinemakom-libmpv")
set(CINEMAKOM_LIBMPV_DLL "${CINEMAKOM_LIBMPV_DIR}/libmpv-2.dll")
set(CINEMAKOM_LIBMPV_STAMP "${CINEMAKOM_LIBMPV_DIR}/.sha256")

set(_cinemakom_need_libmpv TRUE)
if(EXISTS "${CINEMAKOM_LIBMPV_DLL}" AND EXISTS "${CINEMAKOM_LIBMPV_STAMP}")
  file(READ "${CINEMAKOM_LIBMPV_STAMP}" _cinemakom_stamp)
  string(STRIP "${_cinemakom_stamp}" _cinemakom_stamp)
  if(_cinemakom_stamp STREQUAL "${CINEMAKOM_LIBMPV_SHA256}")
    set(_cinemakom_need_libmpv FALSE)
  endif()
endif()

if(_cinemakom_need_libmpv)
  message(STATUS "Downloading current libmpv (${CINEMAKOM_LIBMPV_VERSION})...")
  file(DOWNLOAD "${CINEMAKOM_LIBMPV_URL}" "${CINEMAKOM_LIBMPV_ARCHIVE}"
    EXPECTED_HASH "SHA256=${CINEMAKOM_LIBMPV_SHA256}"
    TLS_VERIFY ON
    STATUS _cinemakom_dl_status)
  list(GET _cinemakom_dl_status 0 _cinemakom_dl_code)
  if(NOT _cinemakom_dl_code EQUAL 0)
    list(GET _cinemakom_dl_status 1 _cinemakom_dl_msg)
    message(FATAL_ERROR "Failed to download ${CINEMAKOM_LIBMPV_URL}: ${_cinemakom_dl_msg}")
  endif()
  file(REMOVE_RECURSE "${CINEMAKOM_LIBMPV_DIR}")
  file(MAKE_DIRECTORY "${CINEMAKOM_LIBMPV_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${CINEMAKOM_LIBMPV_ARCHIVE}" libmpv-2.dll
    WORKING_DIRECTORY "${CINEMAKOM_LIBMPV_DIR}"
    RESULT_VARIABLE _cinemakom_tar_res)
  if(NOT _cinemakom_tar_res EQUAL 0 OR NOT EXISTS "${CINEMAKOM_LIBMPV_DLL}")
    message(FATAL_ERROR "Failed to extract libmpv-2.dll from ${CINEMAKOM_LIBMPV_ARCHIVE}")
  endif()
  file(WRITE "${CINEMAKOM_LIBMPV_STAMP}" "${CINEMAKOM_LIBMPV_SHA256}\n")
endif()

list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX "libmpv-2\\.dll$")
list(APPEND PLUGIN_BUNDLED_LIBRARIES "${CINEMAKOM_LIBMPV_DLL}")


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the hook/build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Bundle the Visual C++ runtime DLLs (msvcp140.dll, vcruntime140.dll,
# vcruntime140_1.dll, etc.) so the app starts on PCs without the Microsoft
# Visual C++ Redistributable installed (docs/PACKAGING.md §4).
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
include(InstallRequiredSystemLibraries)
if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    CONFIGURATIONS Profile;Release
    COMPONENT Runtime)
endif()
