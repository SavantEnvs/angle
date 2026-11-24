// fuzz_load_astc.cc: ANGLE's CPU ASTC decoder (src/image_util/loadimage_astc.cpp ->
// AstcDecompressor.cpp -> astc-encoder), which decodes glCompressedTexImage* ASTC data
// (WebGL-reachable through WEBGL_compressed_texture_astc) when the backend lacks native ASTC.
//
// Input: [0] block footprint index, [1] width-1, [2] height-1, [3] depth-1 (low bit), then blocks.
// The footprints are the 14 2D block sizes GL_KHR_texture_compression_astc_ldr defines (the only
// ones libANGLE's format table instantiates LoadASTCToRGBA8<w,h> for). GL validates that the
// compressed image size equals ceil(w/bw)*ceil(h/bh)*depth*16 before a loader runs
// (ValidCompressedImageSize), so shorter inputs are rejected; the output buffer is exactly the
// RGBA8 image the renderer allocates.
//
// State kept across inputs on purpose: AstcDecompressor's singleton caches one astcenc context per
// block size (as in the browser process); each decompress() resets it (astcenc_decompress_reset),
// so the context holds no data from a previous input.
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "common/WorkerThread.h"
#include "image_util/loadimage.h"

using namespace angle;

namespace
{
struct Footprint
{
    uint32_t w, h;
};
const Footprint kFootprints[] = {{4, 4},  {5, 4},  {5, 5},  {6, 5},   {6, 6},   {8, 5},   {8, 6},
                                 {8, 8},  {10, 5}, {10, 6}, {10, 8},  {10, 10}, {12, 10}, {12, 12}};
constexpr size_t kNumFootprints = sizeof(kFootprints) / sizeof(kFootprints[0]);
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 4)
        return -1;
    const Footprint &fp = kFootprints[data[0] % kNumFootprints];
    const size_t width  = size_t(data[1] % 64) + 1;
    const size_t height = size_t(data[2] % 64) + 1;
    const size_t depth  = size_t(data[3] % 2) + 1;
    data += 4;
    size -= 4;

    const size_t blocksX         = (width + fp.w - 1) / fp.w;
    const size_t blocksY         = (height + fp.h - 1) / fp.h;
    const size_t inputRowPitch   = blocksX * 16;
    const size_t inputDepthPitch = inputRowPitch * blocksY;
    const size_t inputSize       = inputDepthPitch * depth;
    if (size < inputSize)
        return -1;
    // Exact-size copy so ASan sees any over-read of the compressed data.
    std::vector<uint8_t> input(data, data + inputSize);

    const size_t outRowPitch   = width * 4;
    const size_t outDepthPitch = outRowPitch * height;
    std::vector<uint8_t> output(outDepthPitch * depth);

    static std::shared_ptr<WorkerThreadPool> pool =
        WorkerThreadPool::Create(ThreadPoolType::Synchronous, 0, nullptr);
    ImageLoadContext context;
    context.singleThreadPool = pool;
    LoadASTCToRGBA8Inner(context, width, height, depth, fp.w, fp.h, input.data(), inputRowPitch,
                         inputDepthPitch, output.data(), outRowPitch, outDepthPitch);
    return 0;
}
