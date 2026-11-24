// fuzz_compiled_shader_state.cc: gl::CompiledShaderState::deserialize
// (src/common/CompiledShaderState.cpp) — the reader for serialized compiled shaders in ANGLE's
// blob cache and program binaries (shader variables, interface blocks, SPIR-V/source payloads)
// over gl::BinaryInputStream.
//
// Input: [0] shader type (mod gl::ShaderType::EnumCount), then the serialized stream.
#include <cstddef>
#include <cstdint>
#include <vector>

#include "common/BinaryStream.h"
#include "common/CompiledShaderState.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return -1;
    const auto type =
        static_cast<gl::ShaderType>(data[0] % static_cast<uint8_t>(gl::ShaderType::EnumCount));
    std::vector<uint8_t> blob(data + 1, data + size);

    gl::BinaryInputStream stream(angle::Span<const uint8_t>(blob.data(), blob.size()));
    gl::CompiledShaderState state(type);
    state.deserialize(stream);
    if (stream.error())
        return 0;

    // Round-trip what was accepted.
    gl::BinaryOutputStream out;
    state.serialize(out);
    return 0;
}
