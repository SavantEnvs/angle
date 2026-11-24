// fuzz_load_paletted.cc: OES_compressed_paletted_texture decoding
// (angle::LoadPalettedToRGBA8Impl, src/image_util/loadimage_paletted.cpp) for the ten GL_PALETTE*_OES
// formats listed in src/libANGLE/renderer/load_functions_table_autogen.cpp.
//
// Input: [0] format index, [1] width-1, [2] height-1, then palette + 4/8-bit indices. GL validates
// the compressed image size (palette bytes + index rows) before loading, so shorter inputs are
// rejected.
#include <cstddef>
#include <cstdint>
#include <vector>

#include "image_util/loadimage.h"

using namespace angle;

namespace
{
struct Fmt
{
    uint32_t indexBits, redBlueBits, greenBits, alphaBits;
};
const Fmt kFormats[] = {{4, 5, 6, 0}, {4, 5, 5, 1}, {4, 8, 8, 0}, {4, 4, 4, 4}, {4, 8, 8, 8},
                        {8, 5, 6, 0}, {8, 5, 5, 1}, {8, 8, 8, 0}, {8, 4, 4, 4}, {8, 8, 8, 8}};
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 3)
        return -1;
    const Fmt &f        = kFormats[data[0] % (sizeof(kFormats) / sizeof(kFormats[0]))];
    const size_t width  = size_t(data[1] % 128) + 1;
    const size_t height = size_t(data[2] % 128) + 1;
    data += 3;
    size -= 3;

    const size_t colorBytes    = (f.redBlueBits * 2 + f.greenBits + f.alphaBits) / 8;
    const size_t paletteBytes  = (size_t(1) << f.indexBits) * colorBytes;
    const size_t inputRowPitch = (width * f.indexBits + 7) / 8;
    const size_t inputSize     = paletteBytes + inputRowPitch * height;
    if (size < inputSize)
        return -1;
    std::vector<uint8_t> input(data, data + inputSize);

    const size_t outRowPitch = width * 4;
    std::vector<uint8_t> output(outRowPitch * height);
    ImageLoadContext context;
    LoadPalettedToRGBA8Impl(context, width, height, 1, f.indexBits, f.redBlueBits, f.greenBits,
                            f.alphaBits, input.data(), inputRowPitch, inputRowPitch * height,
                            output.data(), outRowPitch, outRowPitch * height);
    return 0;
}
