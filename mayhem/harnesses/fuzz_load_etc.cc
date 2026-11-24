// fuzz_load_etc.cc: ANGLE's ETC1/ETC2/EAC block decoders and ETC->BC transcoders
// (src/image_util/loadimage_etc.cpp), which decode glCompressedTexImage* data (WebGL-reachable)
// when the backend lacks native ETC support.
//
// Input: [0] loader index, [1] width-1, [2] height-1, [3] depth-1 (low 2 bits), then block data.
// GL validates that the compressed image size equals ceil(w/4)*ceil(h/4)*depth*blockBytes before a
// loader runs (ValidCompressedImageSize), so inputs shorter than that are rejected; the output buffer
// is exactly what the renderer would allocate for the destination format.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

#include "image_util/loadimage.h"

using namespace angle;

namespace
{
using LoadFn = void (*)(const ImageLoadContext &, size_t, size_t, size_t, const uint8_t *, size_t,
                        size_t, uint8_t *, size_t, size_t);

struct Loader
{
    LoadFn fn;
    size_t inBlockBytes;   // compressed input bytes per 4x4 block
    size_t outBytes;       // bytes per output pixel, or per output 4x4 block when outIsBlock
    bool outIsBlock;
};

const Loader kLoaders[] = {
    {LoadETC1RGB8ToRGBA8, 8, 4, false},        {LoadETC1RGB8ToBC1, 8, 8, true},
    {LoadEACR11ToR8, 8, 1, false},             {LoadEACR11SToR8, 8, 1, false},
    {LoadEACRG11ToRG8, 16, 2, false},          {LoadEACRG11SToRG8, 16, 2, false},
    {LoadEACR11ToR16, 8, 2, false},            {LoadEACR11SToR16, 8, 2, false},
    {LoadEACRG11ToRG16, 16, 4, false},         {LoadEACRG11SToRG16, 16, 4, false},
    {LoadEACR11ToR16F, 8, 2, false},           {LoadEACR11SToR16F, 8, 2, false},
    {LoadEACRG11ToRG16F, 16, 4, false},        {LoadEACRG11SToRG16F, 16, 4, false},
    {LoadETC2RGB8ToRGBA8, 8, 4, false},        {LoadETC2RGB8ToBC1, 8, 8, true},
    {LoadETC2SRGB8ToRGBA8, 8, 4, false},       {LoadETC2SRGB8ToBC1, 8, 8, true},
    {LoadETC2RGB8A1ToRGBA8, 8, 4, false},      {LoadETC2RGB8A1ToBC1, 8, 8, true},
    {LoadETC2SRGB8A1ToRGBA8, 8, 4, false},     {LoadETC2SRGB8A1ToBC1, 8, 8, true},
    {LoadETC2RGBA8ToBC3, 16, 16, true},        {LoadETC2SRGBA8ToBC3, 16, 16, true},
    {LoadEACR11ToBC4, 8, 8, true},             {LoadEACR11SToBC4, 8, 8, true},
    {LoadEACRG11ToBC5, 16, 16, true},          {LoadEACRG11SToBC5, 16, 16, true},
    {LoadETC2RGBA8ToRGBA8, 16, 4, false},      {LoadETC2SRGBA8ToSRGBA8, 16, 4, false},
};
constexpr size_t kNumLoaders = sizeof(kLoaders) / sizeof(kLoaders[0]);
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 4)
        return -1;
    const Loader &l     = kLoaders[data[0] % kNumLoaders];
    const size_t width  = size_t(data[1] % 64) + 1;
    const size_t height = size_t(data[2] % 64) + 1;
    const size_t depth  = size_t(data[3] % 4) + 1;
    data += 4;
    size -= 4;

    const size_t blocksX         = (width + 3) / 4;
    const size_t blocksY         = (height + 3) / 4;
    const size_t inputRowPitch   = blocksX * l.inBlockBytes;
    const size_t inputDepthPitch = inputRowPitch * blocksY;
    const size_t inputSize       = inputDepthPitch * depth;
    if (size < inputSize)
        return -1;
    // Exact-size copy so ASan sees any over-read of the compressed data.
    std::vector<uint8_t> input(data, data + inputSize);

    size_t outRowPitch, outDepthPitch;
    if (l.outIsBlock)
    {
        outRowPitch   = blocksX * l.outBytes;
        outDepthPitch = outRowPitch * blocksY;
    }
    else
    {
        outRowPitch   = width * l.outBytes;
        outDepthPitch = outRowPitch * height;
    }
    std::vector<uint8_t> output(outDepthPitch * depth);

    ImageLoadContext context;
    l.fn(context, width, height, depth, input.data(), inputRowPitch, inputDepthPitch,
         output.data(), outRowPitch, outDepthPitch);
    return 0;
}
