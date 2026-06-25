# PATCHED by robocup-ss2d-2027 build harness.
# Upstream uses ExternalProject_Add to git-clone rapidjson at build
# time. Outbound git is restricted in some sandboxes; instead we fetch
# the same rapidjson commit (f54b0e47) via our tarball fetcher into
# externals/src/rapidjson/ and point RAPIDJSON_INCLUDE_DIR at it.
get_filename_component(_SRC_ROOT "${CMAKE_SOURCE_DIR}/.." ABSOLUTE)
set(RAPIDJSON_INCLUDE_DIR "${_SRC_ROOT}/rapidjson/include")
if(NOT EXISTS "${RAPIDJSON_INCLUDE_DIR}/rapidjson/document.h")
    message(FATAL_ERROR
        "rapidjson not found at ${RAPIDJSON_INCLUDE_DIR}. "
        "Run: bash scripts/fetch_externals.sh --only rapidjson")
endif()
