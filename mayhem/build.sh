#!/usr/bin/env bash
#
# mayhem/build.sh — build ANGLE's fuzz targets and the translator test oracle.
#
# Upstream builds with GN after a gclient sync of ~40 third_party trees. The fuzzed code here (the
# GLSL ES shader translator + preprocessor, the SPIR-V parser, SHA-1/xxHash, the compressed-texture
# decoders and the compiled-shader deserializer) needs none of them except SPIRV-Headers/SPIRV-Tools
# and astc-encoder (plus googletest for the unit tests), which the Dockerfile caches under
# /opt/toolchains/deps at upstream's DEPS pins. So the sources are
# compiled directly with clang into out/mayhem (gitignored by upstream's `out` rule):
#   out/mayhem/fuzz  — the project + harnesses, with $SANITIZER_FLAGS + libFuzzer coverage + DWARF 3
#   out/mayhem/test  — the same project sources with normal flags, linked into upstream's
#                      angle_unittests (compiler/preprocessor/common/image_util suites) and its
#                      samples/shader_translator CLI; mayhem/test.sh runs both
# Every object is rebuilt on each run (idempotent; no network).
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${SPIRV_HEADERS_DIR:=/opt/toolchains/deps/spirv-headers-fb1379425b16e58dcbdda7be0f8604a7f5cdce78}"
: "${SPIRV_TOOLS_DIR:=/opt/toolchains/deps/spirv-tools-4a21a48a3840e6e47ded4f1951f7d301b9fc37c3}"
: "${GOOGLETEST_DIR:=/opt/toolchains/deps/googletest-a46a6012a133c7c0929fdae55b321c2fe65f3c5f}"
: "${ASTCENC_DIR:=/opt/toolchains/deps/astc-encoder-2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT="$SRC/out/mayhem"
GEN="$OUT/gen"
mkdir -p "$GEN/angle"

# Generated headers, made by upstream's own generator scripts (GN actions in BUILD.gn).
python3 src/commit_id.py gen "$GEN/angle/angle_commit.h"
printf '%s\n' src/common/CompiledShaderState.cpp src/common/CompiledShaderState.h \
  include/GLSLANG/ShaderLang.h include/GLSLANG/ShaderVars.h > "$GEN/program_files.rsp"
python3 src/program_serialize_data_version.py "$GEN/angle/ANGLEShaderProgramVersion.h" "$GEN/program_files.rsp"

# The MSL and WGSL backends (src/compiler/translator/msl, tree_ops/msl, wgsl, tree_ops/wgsl) are built
# as BUILD.gn does with angle_enable_msl / angle_enable_wgpu (OSS-Fuzz turns both on): they include only
# ANGLE and GLES headers, no Metal or Dawn/Tint.
DEFINES=(-DANGLE_ENABLE_ESSL -DANGLE_ENABLE_GLSL -DANGLE_ENABLE_HLSL -DANGLE_ENABLE_VULKAN
         -DANGLE_ENABLE_METAL -DANGLE_ENABLE_WGPU
         -DANGLE_DISABLE_POOL_ALLOC -DGL_GLES_PROTOTYPES=0 -DEGL_EGL_PROTOTYPES=0
         -DANGLE_HAS_ASTCENC -DASTCENC_DECOMPRESS_ONLY=1)
INCLUDES=(-I"$SRC/include" -I"$SRC/src" -I"$SRC/src/common/base" -I"$SRC/src/common/third_party/xxhash/src"
          -I"$SPIRV_HEADERS_DIR/include" -I"$SPIRV_TOOLS_DIR/include" -I"$ASTCENC_DIR/src/Source" -I"$GEN/angle" -I"$GEN")
# Chromium builds against libc++, whose headers pull in <variant>/<iostream> transitively; upstream's
# wgsl/PullExpressionsIntoFunctions.cpp and wgsl/RewritePipelineVariables.cpp rely on that and do not
# compile against the base image's libstdc++ without it.
WARN=(-w -include variant -include iostream)

# ---- source lists ---------------------------------------------------------------------------
mapfile -t TRANSLATOR < <(
  find src/compiler/translator src/compiler/preprocessor -name '*.cpp' \
    -not -path '*/ir/*' -not -path '*/null/*' -not -path '*/apple/*' -not -name '*_unittest.cpp' \
  | LC_ALL=C sort)
COMMON=(src/common/PoolAlloc.cpp src/common/aligned_memory.cpp src/common/debug.cpp
        src/common/angleutils.cpp src/common/mathutil.cpp src/common/string_utils.cpp
        src/common/utilities.cpp src/common/PackedEnums.cpp src/common/PackedGLEnums_autogen.cpp
        src/common/PackedEGLEnums_autogen.cpp src/common/PackedCLEnums_autogen.cpp
        src/common/Float16ToFloat32.cpp src/common/MemoryBuffer.cpp src/common/system_utils.cpp
        src/common/system_utils_posix.cpp src/common/system_utils_linux.cpp src/common/tls.cpp
        src/common/uniform_type_info_autogen.cpp src/common/platform_helpers.cpp
        src/common/event_tracer.cpp src/common/SimpleMutex.cpp src/common/CompiledShaderState.cpp
        src/common/entry_points_enum_autogen.cpp src/common/angle_version_info.cpp
        src/common/base/anglebase/sha1.cc
        src/common/spirv/spirv_instruction_builder_autogen.cpp
        src/common/spirv/spirv_instruction_parser_autogen.cpp
        src/common/spirv/angle_spirv_utils.cpp
        src/image_util/loadimage.cpp src/image_util/loadimage_etc.cpp
        src/image_util/loadimage_paletted.cpp src/image_util/imageformats.cpp
        src/image_util/copyimage.cpp src/image_util/loadimage_astc.cpp
        src/image_util/AstcDecompressor.cpp src/common/WorkerThread.cpp)
# astc-encoder's decoder, the file list of upstream's third_party/astc-encoder/BUILD.gn
mapfile -t ASTCENC < <(sed -n 's@^ *"src/Source/\(astcenc_[a-z_]*\.cpp\)",@'"$ASTCENC_DIR"'/src/Source/\1@p' \
  third_party/astc-encoder/BUILD.gn)
[ "${#ASTCENC[@]}" -gt 20 ] || { echo "astc-encoder source list not found" >&2; exit 1; }
COMMON+=("${ASTCENC[@]}")
C_SOURCES=(src/common/third_party/xxhash/src/xxhash.c)

# compile_lib <dir> <flags...>: compile every source into <dir>/obj and archive libangle.a
compile_lib() {
  local dir="$1"; shift
  rm -rf "$dir/obj" "$dir/libangle.a"; mkdir -p "$dir/obj"
  printf '%s\n' "${TRANSLATOR[@]}" "${COMMON[@]}" | xargs -P "$MAYHEM_JOBS" -I{} sh -c \
    'o="$0/obj/$(echo "{}" | tr / _).o"; exec '"$CXX"' -std=c++20 -c "$@" "{}" -o "$o"' \
    "$dir" "$@" "${DEFINES[@]}" "${INCLUDES[@]}" "${WARN[@]}"
  for s in "${C_SOURCES[@]}"; do
    $CC -c "$@" "${INCLUDES[@]}" "$s" -o "$dir/obj/$(echo "$s" | tr / _).o"
  done
  ar rcs "$dir/libangle.a" "$dir"/obj/*.o
}

LIBS=("$SPIRV_TOOLS_DIR/lib/libSPIRV-Tools.a" -ldl -lpthread)

# ---- 1) test-oracle build: normal flags --------------------------------------------------------
TEST="$OUT/test"
compile_lib "$TEST" -O1 $COVERAGE_FLAGS
$CXX -std=c++20 -O1 $COVERAGE_FLAGS "${DEFINES[@]}" "${INCLUDES[@]}" "${WARN[@]}" \
  samples/shader_translator/shader_translator.cpp "$TEST/libangle.a" "${LIBS[@]}" \
  -o "$TEST/shader_translator"

# ---- 1b) upstream's unit tests (angle_unittests subset), normal flags, linked against TEST's lib --------
# The sources are read from upstream's src/tests/angle_unittests.gni: the src/common, src/image_util and
# preprocessor_tests files of angle_unittests_sources, plus angle_unittests_compiler_tests_sources and the
# HLSL/MSL/WGSL compiler tests (BUILD.gn adds those when the backend is enabled; all three are here).
# The rest of angle_unittests (libANGLE, util/, gpu_info_util, feature_support_util, test_expectations,
# the TestSuite runner) needs libANGLE and the GL/EGL front end, which this build does not compile.
# UT_EXCLUDE: files from those lists that are not built, each with its reason.
declare -A UT_EXCLUDE=(
  # includes util/test_utils.h from upstream's util/ test library (process launching), not built here
  [src/common/system_utils_unittest.cpp]=util
  # its std::set<raw_ref<int>> needs std::less<raw_ref>, which only libc++ (Chromium's STL) provides
  [src/common/partition_alloc/raw_ref_unittest.cpp]=libc++
)
gni_list() { awk -v n="$1" '$0 ~ "^" n " = \\[" {f=1} f {print} f && /\]/ {f=0}' src/tests/angle_unittests.gni \
  | grep -o '"[^"]*\.cpp"' | tr -d '"'; }
mapfile -t UT_SRCS < <(
  { gni_list angle_unittests_sources | grep -E '^(\.\./common/|\.\./image_util/|preprocessor_tests/|test_utils/compiler_test)'
    gni_list angle_unittests_compiler_tests_sources
    gni_list angle_unittests_hlsl_sources
    gni_list angle_unittests_msl_sources | grep '^\.\./tests/compiler_tests/'
    gni_list angle_unittests_wgsl_sources
    echo compiler_tests/ImmutableString_test_autogen.cpp
  } | while read -r f; do p="$(realpath -m --relative-to=. "src/tests/$f")"; [ -n "${UT_EXCLUDE[$p]:-}" ] || echo "$p"; done)
[ "${#UT_SRCS[@]}" -gt 50 ] || { echo "angle_unittests source list not found" >&2; exit 1; }
UT="$TEST/unittests"
rm -rf "$UT"; mkdir -p "$UT/obj"
# Two angle_common/libANGLE sources only the tests use: Mat4 (matrix_utils_unittest) and
# ANGLEPlatformCurrent() (WorkerThread_unittest, AstcDecompressor_unittest; upstream's Platform.cpp).
printf '%s\n' "${UT_SRCS[@]}" src/common/matrix_utils.cpp src/libANGLE/Platform.cpp mayhem/tests/unittest_main.cc | xargs -P "$MAYHEM_JOBS" -I{} sh -c \
  'exec '"$CXX"' -std=c++20 -c "$@" "{}" -o "$0/obj/$(echo "{}" | tr / _).o"' \
  "$UT" -O1 $COVERAGE_FLAGS "${DEFINES[@]}" "${INCLUDES[@]}" -I"$SRC/src/tests" -I"$SRC/src/tests/preprocessor_tests" \
  -I"$GOOGLETEST_DIR/include" "${WARN[@]}"
$CXX -O1 $COVERAGE_FLAGS "$UT"/obj/*.o "$TEST/libangle.a" "$GOOGLETEST_DIR/lib/libgmock.a" \
  "$GOOGLETEST_DIR/lib/libgtest.a" "${LIBS[@]}" -o "$TEST/angle_unittests"

# ---- 2) fuzz build: sanitizers + coverage + DWARF 3 -------------------------------------------
FUZZ="$OUT/fuzz"
# UBSan's `enum` check is relaxed (only when sanitizers are on): both translator harnesses copy the
# raw header word into a ShShaderOutput and pass it to sh::IsOutput*() (util.cpp) before checking
# it against the valid outputs, so the check fires on nearly every input. ASan and the rest of
# UBSan stay on and halting.
RELAX=(); [ -n "$SANITIZER_FLAGS" ] && RELAX=(-fno-sanitize=enum)
FFLAGS=(-O1 $SANITIZER_FLAGS "${RELAX[@]}" $DEBUG_FLAGS -fsanitize=fuzzer-no-link)
compile_lib "$FUZZ" "${FFLAGS[@]}"
$CC "${FFLAGS[@]}" -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ/standalone_main.o"
$CXX "${FFLAGS[@]}" -c mayhem/lsan_off.cc -o "$FUZZ/lsan_off.o"

# name -> harness source
declare -A HARNESS=(
  [fuzz_translator]=mayhem/harnesses/fuzz_translator.cc
  [fuzz_preprocessor]=mayhem/harnesses/fuzz_preprocessor.cc
  [fuzz_sha1]=mayhem/harnesses/fuzz_sha1.cc
  [fuzz_spirv_parser]=mayhem/harnesses/fuzz_spirv_parser.cc
  [fuzz_load_etc]=mayhem/harnesses/fuzz_load_etc.cc
  [fuzz_load_paletted]=mayhem/harnesses/fuzz_load_paletted.cc
  [fuzz_load_astc]=mayhem/harnesses/fuzz_load_astc.cc
  [fuzz_compiled_shader_state]=mayhem/harnesses/fuzz_compiled_shader_state.cc
  [fuzz_resource_name]=mayhem/harnesses/fuzz_resource_name.cc
  [translator_fuzzer]=src/compiler/fuzz/translator_fuzzer.cpp
  [xxhash_fuzzer]=src/common/third_party/xxhash/xxhash_fuzzer.cpp
)
for name in "${!HARNESS[@]}"; do
  src="${HARNESS[$name]}"
  $CXX -std=c++20 "${FFLAGS[@]}" "${DEFINES[@]}" "${INCLUDES[@]}" "${WARN[@]}" -c "$src" -o "$FUZZ/$name.o"
  $CXX "${FFLAGS[@]}" $LIB_FUZZING_ENGINE "$FUZZ/$name.o" "$FUZZ/lsan_off.o" "$FUZZ/libangle.a" "${LIBS[@]}" \
    -o "$SRC/$name"
  $CXX "${FFLAGS[@]/-fsanitize=fuzzer-no-link/}" "$FUZZ/standalone_main.o" "$FUZZ/$name.o" "$FUZZ/lsan_off.o" \
    "$FUZZ/libangle.a" "${LIBS[@]}" -o "$SRC/$name-standalone"
done
echo "built: ${!HARNESS[*]}"
